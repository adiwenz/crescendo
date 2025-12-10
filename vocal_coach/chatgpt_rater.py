#!/usr/bin/env python3
"""
Send a vocal take (raw WAV) to ChatGPT for feedback and a "goodness score".

For now this prints the feedback to the terminal. If no API key is available
or --mock is passed, it prints a sample response.

Usage:
  python chatgpt_rater.py --audio ../audio_files/TAKE.wav --model gpt-4o-audio-preview
  python chatgpt_rater.py --audio ../audio_files/TAKE.wav --mock

Auth:
  - Set OPENAI_API_KEY (can be stored in a local .env), or
  - Use `gcloud auth application-default login` and set OPENAI_API_KEY manually.
    (This script does not auto-read gcloud tokens.)
"""

import argparse
import base64
import json
import os
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv

load_dotenv()

SAMPLE_FEEDBACK = "whoops"
# SAMPLE_FEEDBACK = """⭐ GOODNESS SCORE (for this take)

# Pitch Accuracy: 78/100
# You landed on the notes, but several onsets scooped upward. Stability was decent once settled. A few transitions sagged before locking in.

# Tone Quality: 82/100
# Your natural resonance is good. Tone clarity is solid but slightly “pulled back.” Occasional breathiness on starts reduces stability.

# Breath Support: 72/100
# You had enough air, but not consistent enough to maintain perfect stability. Onsets revealed the biggest inconsistency.

# Resonance Placement: 80/100
# You’re in a healthy mix most of the time. Tongue root tension and under-lifted soft palate dull the clarity occasionally.

# Intonation + Control: 76/100
# The center is correct. The attack onto the note is where points dropped.

# 🎤 Overall Goodness Score: 78/100
# This is a solid take — not beginner quality, not perfect, but clearly someone with vocal awareness who is building real control.
# If you sang this for a vocal coach, they'd say: “You're talented. Now let's clean up your onsets and breath consistency.”"""


SYSTEM_PROMPT = """You are a vocal coach. Given an audio take, return concise scoring and feedback.
Keep it short and skimmable. Always include:
- Pitch Accuracy (0-100)
- Tone Quality (0-100)
- Breath Support (0-100)
- Resonance Placement (0-100)
- Intonation + Control (0-100)
- Overall Goodness Score (0-100)
Then give 2-3 actionable bullets on how to improve the weakest areas.
Return plain text, no markdown beyond simple bullets."""


def load_audio_b64(path: Path) -> str:
    data = path.read_bytes()
    return base64.b64encode(data).decode("utf-8")


def maybe_call_openai(audio_path: Path, model: str, mock: bool) -> str:
    """Try to call OpenAI; fall back to mock if missing deps/keys or on error."""
    if mock:
        return SAMPLE_FEEDBACK

    try:
        import openai  # type: ignore
    except Exception:
        return SAMPLE_FEEDBACK + "\n\n[Mocked: openai package not available]"

    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        return SAMPLE_FEEDBACK + "\n\n[Mocked: OPENAI_API_KEY not set]"

    client = openai.OpenAI(api_key=api_key)
    audio_b64 = load_audio_b64(audio_path)

    def parse_chat_completion(completion: object) -> Optional[str]:
        """Pull a text string out of a Chat Completions response."""
        try:
            message = completion.choices[0].message  # type: ignore
        except Exception:
            return None
        content = getattr(message, "content", None)
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text" and isinstance(block.get("text"), str):
                    return block["text"]
                if hasattr(block, "type") and getattr(block, "type") == "text":
                    text_val = getattr(block, "text", None)
                    if isinstance(text_val, str):
                        return text_val
        return None

    try:
        # Prefer the newer Responses API when available.
        if hasattr(client, "responses") and hasattr(client.responses, "create"):
            try:
                resp = client.responses.create(
                    model=model,
                    input=[
                        {"role": "system", "content": [{"type": "input_text", "text": SYSTEM_PROMPT}]},
                        {
                            "role": "user",
                            "content": [
                                {"type": "input_text", "text": "Evaluate this vocal take. Focus strictly on vocal coaching, not transcription."},
                                {"type": "input_audio", "input_audio": {"data": audio_b64, "format": "wav"}},
                            ],
                        },
                    ],
                )
                if getattr(resp, "output_text", None):
                    return resp.output_text  # type: ignore[attr-defined]
                output = getattr(resp, "output", None)
                if output and output[0].content:
                    for block in output[0].content:
                        if getattr(block, "type", None) == "output_text":
                            return getattr(block, "text", SAMPLE_FEEDBACK)  # type: ignore[attr-defined]
                debug_content = None
                try:
                    debug_content = json.dumps(resp.model_dump(), indent=2)  # type: ignore[attr-defined]
                except Exception:
                    debug_content = repr(resp)
                return SAMPLE_FEEDBACK + "\n\n[Error: Unexpected Responses API shape. Full payload was:]\n" + str(debug_content)
            except Exception as e_resp:
                # Fall back to Chat Completions if Responses is not supported yet.
                fallback_error = f"[Responses API failed: {e_resp}] "
        else:
            fallback_error = ""

        completion = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": [{"type": "text", "text": SYSTEM_PROMPT}]},
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": "Evaluate this vocal take. Focus strictly on vocal coaching, not transcription."},
                        {"type": "input_audio", "input_audio": {"data": audio_b64, "format": "wav"}},
                    ],
                },
            ],
        )
        parsed = parse_chat_completion(completion)
        if parsed:
            return parsed

        debug_content = None
        try:
            debug_content = json.dumps(completion.model_dump(), indent=2)  # type: ignore[attr-defined]
        except Exception:
            debug_content = repr(completion)
        return SAMPLE_FEEDBACK + f"\n\n[Error: Unexpected Chat Completions response shape. {fallback_error}Full payload was:]\n" + str(debug_content)
    except Exception as e:
        return SAMPLE_FEEDBACK + f"\n\n[Mocked: OpenAI call failed: {e}]"


def main():
    ap = argparse.ArgumentParser(description="Send a vocal take WAV to ChatGPT for scoring/feedback.")
    ap.add_argument("--audio", required=True, help="Path to WAV take")
    ap.add_argument(
        "--model",
        default="gpt-4o-audio-preview",
        help="OpenAI model to use (e.g., gpt-4o-audio-preview or gpt-4o-mini-audio-preview; must support audio input via Chat Completions API).",
    )
    ap.add_argument("--mock", action="store_true", help="Force mock response (no API call)")
    args = ap.parse_args()

    audio_path = Path(args.audio)
    if not audio_path.exists():
        raise FileNotFoundError(f"Audio not found: {audio_path}")

    feedback = maybe_call_openai(audio_path, args.model, args.mock)
    print(feedback)


if __name__ == "__main__":
    main()
