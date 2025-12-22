# audio_time_stretch.py

import argparse
from pathlib import Path

import librosa
import soundfile as sf


def slow_down_audio(
    input_path: str,
    output_path: str,
    rate: float = 0.5,
    target_sr: int | None = None
):
    """
    Time-stretch audio while preserving pitch.

    Args:
        input_path: path to input audio file
        output_path: path to output audio file
        rate: playback speed (0.5 = half speed, 0.75 = 25% slower)
        target_sr: optional resample rate (None keeps original)
    """

    input_path = Path(input_path)
    output_path = Path(output_path)

    y, sr = librosa.load(input_path, sr=target_sr, mono=True)

    # Time-stretch (phase vocoder)
    y_slow = librosa.effects.time_stretch(y, rate=rate)

    sf.write(output_path, y_slow, sr)

    return {
        "input": str(input_path),
        "output": str(output_path),
        "rate": rate,
        "sample_rate": sr,
        "duration_in": len(y) / sr,
        "duration_out": len(y_slow) / sr,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Time-stretch a WAV while preserving pitch.")
    parser.add_argument("input", help="Path to input WAV")
    parser.add_argument("output", help="Path to output WAV")
    parser.add_argument("--rate", type=float, default=0.5, help="Playback speed (0.5=half speed, 1.0=no change)")
    parser.add_argument("--target_sr", type=int, default=None, help="Optional resample rate (defaults to source SR)")
    args = parser.parse_args()

    slow_down_audio(
        args.input,
        args.output,
        rate=args.rate,
        target_sr=args.target_sr,
    )
