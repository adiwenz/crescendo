import argparse
import os
from pathlib import Path

from dotenv import load_dotenv
from openai import OpenAI


def main():
    parser = argparse.ArgumentParser(description="Generate TTS from GPT-4o Mini TTS.")
    parser.add_argument("--voice", default="ballad", help="Voice name (e.g., alloy, echo, fable, onyx, nova, shimmer)")
    parser.add_argument("--text", default="Hello from a secure environment variable!", help="Text to synthesize")
    parser.add_argument("--output", default="tts_output.mp3", help="Output mp3 path")
    parser.add_argument("--model", default="gpt-4o-mini-tts", help="TTS model to use")
    args = parser.parse_args()

    load_dotenv()
    client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

    resp = client.audio.speech.create(
        model=args.model,
        voice=args.voice,
        input=args.text,
    )

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("wb") as f:
        f.write(resp.read())

    print(f"Saved {out_path}")


if __name__ == "__main__":
    main()
