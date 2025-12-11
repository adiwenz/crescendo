#!/usr/bin/env python3
"""
Shared utilities for calling ChatGPT on a vocal take and returning structured feedback.
"""
import base64
import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

from dotenv import load_dotenv

load_dotenv()

DEFAULT_MODEL = "gpt-4o-audio-preview"


@dataclass
class ChatGPTFeedback:
    metrics: Dict[str, Dict[str, Any]]
    summary: str
    recommendations: List[str]
    model: str
    source: str
    raw_text: str
    error: Optional[str] = None
    pitch_contour: Optional[List[Dict[str, Any]]] = None

    def to_dict(self) -> Dict[str, Any]:
        data = {
            "metrics": self.metrics,
            "summary": self.summary,
            "recommendations": self.recommendations,
            "model": self.model,
            "source": self.source,
            "raw_text": self.raw_text,
            **({"error": self.error} if self.error else {}),
        }
        if self.pitch_contour is not None:
            data["pitch_contour"] = self.pitch_contour
        return data


SAMPLE_FEEDBACK = ChatGPTFeedback(
    metrics={
        "pitch_accuracy": {"score": 78, "explanation": "Mostly on pitch with minor scoops.", "improvement_recommendation": "Land directly on target notes; practice slow slides with a tuner."},
        "tone_quality": {"score": 82, "explanation": "Clear tone with occasional pull-back.", "improvement_recommendation": "Keep forward resonance on vowels for consistent brightness."},
        "breath_support": {"score": 72, "explanation": "Airflow sags on sustained phrases.", "improvement_recommendation": "Do steady hiss/“vv” exercises to stabilize support."},
        "resonance_placement": {"score": 80, "explanation": "Mostly balanced placement with slight dullness at times.", "improvement_recommendation": "Lift soft palate and keep tongue relaxed to avoid dampening."},
        "intonation_control": {"score": 76, "explanation": "Attacks sometimes slide; centers are solid once settled.", "improvement_recommendation": "Practice clean onsets into sustained vowels to reduce scoops."},
        "overall_score": {"score": 78, "explanation": "Generally solid take with room for steadier breath and cleaner onsets.", "improvement_recommendation": "Combine breath drills with slow, accurate note entries."},
    },
    summary="Solid take with good resonance; work on onsets and steadier breath for higher consistency.",
    recommendations=[
        "Practice clean onsets: start notes with gentle but firm cord closure to avoid scooping.",
        "Keep airflow even through longer phrases; avoid early breath leaks.",
        "Use forward resonance on vowels to keep clarity across transitions.",
    ],
    model=DEFAULT_MODEL,
    source="sample",
    raw_text="Sample fallback feedback.",
    pitch_contour=[{"time": t / 10.0, "pitch": 200 + (t % 30)} for t in range(50)],
)

SYSTEM_PROMPT = """You are a vocal coach. Given an audio take, return JSON only.
The JSON must follow this shape:
{
  "metrics": {
    "pitch_accuracy": { "score": 0-100, "explanation": "why you chose this score", "improvement_recommendation": "specific action to improve this metric" },
    "tone_quality": { "score": 0-100, "explanation": "...", "improvement_recommendation": "..." },
    "breath_support": { "score": 0-100, "explanation": "...", "improvement_recommendation": "..." },
    "resonance_placement": { "score": 0-100, "explanation": "...", "improvement_recommendation": "..." },
    "intonation_control": { "score": 0-100, "explanation": "...", "improvement_recommendation": "..." },
    "overall_score": { "score": 0-100, "explanation": "overall takeaway", "improvement_recommendation": "overall priority" }
  },
  "summary": "1-2 sentences summarizing the take",
  "recommendations": ["3 concise bullet points to improve weakest areas"],
  "local_pitch_accuracy": { "score": 0-100,}  // optional, should be the locked_metrics pitch_accuracy 
  "pitch_contour": [ { "time": seconds, "pitch": hz } ] // optional contour sampled ~10 Hz
}
No markdown, no extra keys, numbers only for scores. For the returned pitch_accuracy score, use locked_metrics={"pitch_accuracy"}.
"""

def _load_audio_b64(path: Path) -> str:
    data = path.read_bytes()
    return base64.b64encode(data).decode("utf-8")


def _parse_chat_completion(completion: Any) -> Optional[str]:
    """Extract text content from a Chat Completions response."""
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


def _safe_parse_json(text: str) -> Optional[Dict[str, Any]]:
    try:
        return json.loads(text)
    except Exception:
        return None


def get_chatgpt_feedback(
    audio_path: Path,
    model: str = DEFAULT_MODEL,
    mock: bool = False,
    analysis_context: Optional[Dict[str, Any]] = None,
    locked_metrics: Optional[Dict[str, float]] = None,
    return_pitch_contour: bool = False,
) -> ChatGPTFeedback:
    """Call OpenAI for vocal feedback; return structured data or sample fallback."""
    if mock:
        fb = SAMPLE_FEEDBACK
        return ChatGPTFeedback(
            metrics=fb.metrics,
            summary=fb.summary,
            recommendations=fb.recommendations,
            model=model,
            source="mock",
            raw_text=fb.raw_text,
            pitch_contour=fb.pitch_contour,
        )

    try:
        import openai  # type: ignore
    except Exception as e:
        fb = SAMPLE_FEEDBACK
        return ChatGPTFeedback(
            metrics=fb.metrics,
            summary=fb.summary,
            recommendations=fb.recommendations,
            model=model,
            source="mock",
            raw_text=fb.raw_text,
            error=f"openai import failed: {e}",
            pitch_contour=fb.pitch_contour,
        )

    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        fb = SAMPLE_FEEDBACK
        return ChatGPTFeedback(
            metrics=fb.metrics,
            summary=fb.summary,
            recommendations=fb.recommendations,
            model=model,
            source="mock",
            raw_text=fb.raw_text,
            error="OPENAI_API_KEY not set",
            pitch_contour=fb.pitch_contour,
        )

    client = openai.OpenAI(api_key=api_key)
    audio_b64 = _load_audio_b64(audio_path)

    try:
        user_content: List[Dict[str, Any]] = [
            {"type": "text", "text": "Evaluate this vocal take."},
        ]
        if analysis_context:
            try:
                ctx_json = json.dumps(analysis_context)
            except Exception:
                ctx_json = str(analysis_context)
            user_content.append(
                {
                    "type": "text",
                    "text": f"Precomputed analysis (use as the basis for numeric scores, especially pitch; adjust only if the audio clearly contradicts): {ctx_json}",
                }
            )
        if locked_metrics:
            locked_text = json.dumps({k: v for k, v in locked_metrics.items()})
            user_content.append(
                {
                    "type": "text",
                    "text": f"Fixed metric scores (do not recompute; set these exact numbers in the JSON; especially for pitch use these exact values): {locked_text}",
                }
            )
        if return_pitch_contour:
            user_content.append(
                {
                    "type": "text",
                    "text": "Also include a pitch_contour array of objects with time (seconds) and pitch (Hz) sampled at ~10 Hz; omit or leave empty if uncertain.",
                }
            )
        user_content.append({"type": "input_audio", "input_audio": {"data": audio_b64, "format": "wav"}})

        completion = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": [{"type": "text", "text": SYSTEM_PROMPT}]},
                {"role": "user", "content": user_content},
            ],
        )
        text = _parse_chat_completion(completion)
        parsed = _safe_parse_json(text) if text else None
        if not parsed:
            fb = SAMPLE_FEEDBACK
            return ChatGPTFeedback(
                metrics=fb.metrics,
                summary=fb.summary,
                recommendations=fb.recommendations,
                model=model,
                source="mock",
                raw_text=text or "",
                error="Could not parse JSON from ChatGPT response",
            )
        metrics = parsed.get("metrics") or {}
        local_pitch = parsed.get("local_pitch_accuracy")
        if isinstance(local_pitch, dict) and "score" in local_pitch:
            metrics.setdefault("local_pitch_accuracy", {})["score"] = local_pitch.get("score")
        recommendations = parsed.get("recommendations") or []
        summary = parsed.get("summary") or ""
        pitch_contour = parsed.get("pitch_contour") if isinstance(parsed.get("pitch_contour"), list) else None
        if not metrics and "scores" in parsed and "improvements" in parsed:
            # Back-compat: combine scores+improvements into metrics blocks.
            scores = parsed.get("scores") or {}
            improvements = parsed.get("improvements") or {}
            metrics = {
                k: {
                    "score": scores.get(k),
                    "explanation": "",
                    "improvement_recommendation": improvements.get(k),
                }
                for k in set(scores) | set(improvements)
            }
        fb = ChatGPTFeedback(
            metrics={
                k: {
                    "score": float(v.get("score")) if isinstance(v.get("score"), (int, float)) else None,
                    "explanation": str(v.get("explanation") or ""),
                    "improvement_recommendation": str(v.get("improvement_recommendation") or ""),
                }
                for k, v in metrics.items()
                if isinstance(v, dict)
            },
            summary=str(summary),
            recommendations=[str(r) for r in recommendations][:5],
            model=model,
            source="openai",
            raw_text=text or json.dumps(parsed),
            pitch_contour=pitch_contour,
        )
        return _apply_locked_metrics(fb, locked_metrics)
    except Exception as e:
        fb = SAMPLE_FEEDBACK
        fb_obj = ChatGPTFeedback(
            metrics=fb.metrics,
            summary=fb.summary,
            recommendations=fb.recommendations,
            model=model,
            source="mock",
            raw_text=fb.raw_text,
            error=str(e),
            pitch_contour=fb.pitch_contour,
        )
        return _apply_locked_metrics(fb_obj, locked_metrics)


def _apply_locked_metrics(feedback: ChatGPTFeedback, locked: Optional[Dict[str, float]]):
    """Override specific metric scores with provided fixed values."""
    if not locked:
        return feedback
    metrics = feedback.metrics or {}
    for key, val in locked.items():
        if key not in metrics:
            metrics[key] = {"score": None, "explanation": "", "improvement_recommendation": ""}
        metrics[key]["score"] = val
    feedback.metrics = metrics
    return feedback


def feedback_to_text(feedback: Dict[str, Any]) -> str:
    metrics = feedback.get("metrics", {})
    summary = feedback.get("summary", "")
    recs = feedback.get("recommendations", [])
    lines = [summary] if summary else []
    order = ["pitch_accuracy", "tone_quality", "breath_support", "resonance_placement", "intonation_control", "overall_score"]
    for key in order:
        m = metrics.get(key, {})
        score = m.get("score", "—")
        expl = m.get("explanation", "")
        imp = m.get("improvement_recommendation", "")
        lines.append(f"{key}: {score}")
        if expl:
            lines.append(f"  why: {expl}")
        if imp:
            lines.append(f"  improve: {imp}")
    if recs:
        lines.append("\nRecommendations:")
        for r in recs:
            lines.append(f"- {r}")
    return "\n".join(lines)
