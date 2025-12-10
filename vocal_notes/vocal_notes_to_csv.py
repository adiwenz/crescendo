#!/usr/bin/env python3
"""
vocal_notes_to_csv.py

Usage:
    python vocal_notes_to_csv.py take1.wav take2.wav ... --output_csv vocal_notes_stats.csv

What it does:
- For each input audio file (vocal take):
    - Loads audio (mono)
    - Estimates pitch over time using librosa.pyin
    - Segments pitch into "notes" based on time gaps and pitch jumps
    - For each note:
        - Computes mean f0
        - Finds nearest equal-tempered note (midi + name)
        - Computes cents error (signed)
    - Aggregates all notes from all takes into ONE CSV.

CSV columns:
    take          - name of the take (basename without extension)
    note_index    - 0-based index per take
    start_time    - note start time (seconds)
    end_time      - note end time (seconds)
    duration      - end_time - start_time
    note_name     - nearest equal-tempered note name (e.g. A3, F#4)
    measured_hz   - average frequency over the note
    target_hz     - nearest note frequency (Hz)
    cents_error   - signed cents (positive = sharp, negative = flat)
    frame_times   - JSON array of timestamps (s) for each voiced frame in the note
    frame_hz      - JSON array of f0 estimates (Hz) matching frame_times
"""

import argparse
import csv
import os
import json
import sys
from pathlib import Path
from typing import Any, Dict, List

# Ensure repo root is on sys.path when running as a script
sys.path.append(str(Path(__file__).resolve().parents[1]))

from vocal_analyzer.pitch_utils import analyze_take


def main():
    parser = argparse.ArgumentParser(
        description="Analyze vocal takes into notes and export cents stats to CSV."
    )
    parser.add_argument("audio_paths", nargs="+",
                        help="Input vocal audio files (e.g., take1.wav take2.wav)")
    parser.add_argument("--output_csv", default="vocal_notes_stats.csv",
                        help="Output CSV path (default: vocal_notes_stats.csv)")
    parser.add_argument("--fmin", type=float, default=80.0,
                        help="Minimum expected f0 (Hz), default 80")
    parser.add_argument("--fmax", type=float, default=1000.0,
                        help="Maximum expected f0 (Hz), default 1000")

    args = parser.parse_args()

    # Convenience: allow last positional arg to be an output CSV path
    if args.output_csv == "vocal_notes_stats.csv" and len(args.audio_paths) > 1 and args.audio_paths[-1].lower().endswith(".csv"):
        args.output_csv = args.audio_paths[-1]
        args.audio_paths = args.audio_paths[:-1]
        print(f"Interpreting last argument as output CSV: {args.output_csv}")

    all_rows: List[Dict[str, Any]] = []

    for audio_path in args.audio_paths:
        take_name = os.path.splitext(os.path.basename(audio_path))[0]
        notes = analyze_take(audio_path, fmin=args.fmin, fmax=args.fmax, verbose=True)

        for n in notes:
            row = {
                "take": take_name,
                **n
            }
            all_rows.append(row)

    if not all_rows:
        print("No notes to write. Exiting.")
        return

    fieldnames = [
        "take",
        "note_index",
        "start_time",
        "end_time",
        "duration",
        "note_name",
        "measured_hz",
        "target_hz",
        "cents_error",
        "frame_times",
        "frame_hz",
    ]

    print(f"\nWriting {len(all_rows)} notes to {args.output_csv}")
    with open(args.output_csv, "w", newline="") as f:
        # write header
        f.write(",".join(fieldnames) + "\n")

        def as_list(v):
            if v is None:
                return []
            if isinstance(v, (list, tuple)):
                return list(v)
            try:
                import numpy as np  # local import to avoid top-level dependency here
                if isinstance(v, np.ndarray):
                    v = v.tolist()
            except Exception:
                pass
            if isinstance(v, (float, int)):
                return [v]
            return list(v) if isinstance(v, (set, dict)) is False else list(v)

        def fmt_scalar(val):
            if isinstance(val, bool):
                return "1" if val else "0"
            if isinstance(val, int):
                return str(val)
            if isinstance(val, float):
                return f"{val}"
            return str(val)

        for row in all_rows:
            frame_times = [float(x) for x in as_list(row.get("frame_times"))]
            frame_hz = [float(x) for x in as_list(row.get("frame_hz"))]

            ft_str = json.dumps(frame_times)
            fh_str = json.dumps(frame_hz)

            parts = []
            for fn in fieldnames:
                if fn == "frame_times":
                    parts.append(f"\"{ft_str}\"")
                elif fn == "frame_hz":
                    parts.append(f"\"{fh_str}\"")
                else:
                    parts.append(fmt_scalar(row[fn]))
            f.write(",".join(parts) + "\n")


if __name__ == "__main__":
    main()
