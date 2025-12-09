#!/usr/bin/env python3
"""
Record a take (press SPACE to stop), then run:
1) vocal_notes/vocal_notes_to_csv.py over all WAVs in audio_files/ -> vocal_notes/vocal_notes_stats.csv
2) inter_take_analysis/generate_take.py for the new take -> inter_take_analysis/takes/<take>.csv
3) inter_take_analysis/build_takes_index.py -> inter_take_analysis/takes_index.json

Requires: sounddevice, soundfile (already in requirements).
"""

import argparse
import os
import sys
import time
import subprocess
import tempfile
import termios
import tty
from pathlib import Path
from typing import List

import numpy as np
import sounddevice as sd
import soundfile as sf


ROOT = Path(__file__).resolve().parent.parent
AUDIO_DIR = ROOT / "audio_files"
TAKES_DIR = ROOT / "inter_take_analysis" / "takes"
VOCAL_NOTES_CSV = ROOT / "vocal_notes" / "vocal_notes_stats.csv"
TAKES_INDEX_JSON = ROOT / "inter_take_analysis" / "takes_index.json"


def wait_for_space(prompt: str = "Recording... press SPACE to stop"):
    """Block until the user presses space (terminal raw mode)."""
    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    tty.setcbreak(fd)
    print(prompt, flush=True)
    try:
        while True:
            ch = sys.stdin.read(1)
            if ch == " ":
                break
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)


def record_take(sr: int = 44100, channels: int = 1) -> np.ndarray:
    """Record audio until spacebar is pressed."""
    frames: List[np.ndarray] = []
    stop_flag = False

    def callback(indata, frames_count, time_info, status):
        nonlocal stop_flag
        if status:
            print(status, file=sys.stderr)
        frames.append(indata.copy())
        if stop_flag:
            raise sd.CallbackStop()

    with sd.InputStream(samplerate=sr, channels=channels, callback=callback):
        wait_for_space()
        stop_flag = True
        # small sleep to let callback exit cleanly
        time.sleep(0.05)

    if not frames:
        raise RuntimeError("No audio captured.")
    audio = np.concatenate(frames, axis=0).squeeze()
    return audio


def run_cmd(cmd: List[str], cwd: Path = ROOT):
    print(f"Running: {' '.join(cmd)}")
    subprocess.run(cmd, check=True, cwd=cwd)


def main():
    ap = argparse.ArgumentParser(description="Record a take, auto-analyze, and refresh indexes.")
    ap.add_argument("--take_name", help="Name for the take (default: take_<timestamp>)")
    ap.add_argument("--samplerate", type=int, default=44100)
    ap.add_argument("--channels", type=int, default=1)
    args = ap.parse_args()

    take = args.take_name or f"take_{int(time.time())}"
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    TAKES_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Take name: {take}")
    audio = record_take(sr=args.samplerate, channels=args.channels)

    out_path = AUDIO_DIR / f"{take}.wav"
    sf.write(out_path, audio, args.samplerate)
    print(f"Wrote {out_path}")

    # Rebuild vocal_notes_stats.csv from all wavs
    wavs = sorted(str(p) for p in AUDIO_DIR.glob("*.wav"))
    if not wavs:
        print("No wavs in audio_files; skipping analysis.")
        return
    run_cmd(
        ["python", str(ROOT / "vocal_notes" / "vocal_notes_to_csv.py"), *wavs, "--output_csv", str(VOCAL_NOTES_CSV)]
    )

    # Generate take CSV for this take
    run_cmd(
        [
            "python",
            str(ROOT / "inter_take_analysis" / "generate_take.py"),
            str(out_path),
            "--output",
            str(TAKES_DIR / f"{take}.csv"),
            "--take_name",
            take,
        ]
    )

    # Rebuild takes_index.json
    run_cmd(
        [
            "python",
            str(ROOT / "inter_take_analysis" / "build_takes_index.py"),
            "--takes_dir",
            str(TAKES_DIR),
            "--output",
            str(TAKES_INDEX_JSON),
        ]
    )

    print("✅ Pipeline complete. Reload dashboards to see the new take.")


if __name__ == "__main__":
    main()
