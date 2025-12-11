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
import os
import json
import sys
import numpy as np
from pathlib import Path
from typing import Any, Dict, List

# Ensure repo root is on sys.path when running as a script
sys.path.append(str(Path(__file__).resolve().parents[1]))

from dutils.pitch_utils import analyze_take


def to_list(value: Any) -> List[Any]:
    """Normalize scalars, numpy arrays, and iterables into a plain list for CSV output."""
    if value is None:
        return []
    if isinstance(value, list):
        return value
    if isinstance(value, tuple):
        return list(value)
    if isinstance(value, np.ndarray):
        return value.tolist()
    if isinstance(value, (float, int)):
        return [value]
    return list(value)


def to_scalar(value: Any) -> str:
    """Format a scalar as a CSV-friendly string (booleans become 1/0)."""
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return f"{value}"
    return str(value)


def collect_note_rows(audio_paths: List[str], fmin: float, fmax: float, verbose: bool = True) -> List[Dict[str, Any]]:
    """Extract notes for each audio take and return flattened rows for CSV writing."""
    rows: List[Dict[str, Any]] = []
    extend_rows = rows.extend
    analyze = analyze_take

    for audio_path in audio_paths:
        take_name = os.path.splitext(os.path.basename(audio_path))[0]
        notes = analyze(audio_path, fmin=fmin, fmax=fmax, verbose=verbose)
        if notes:
            extend_rows({"take": take_name, **n} for n in notes)

    return rows


def write_rows(rows: List[Dict[str, Any]], output_csv: str, fieldnames: List[str]) -> None:
    """Write rows to CSV with pre-bound helpers to minimize per-row overhead."""
    with open(output_csv, "w", newline="") as f:
        f.write(",".join(fieldnames) + "\n")

        for row in rows:
            frame_times = [float(x) for x in to_list(row.get("frame_times"))]
            frame_hz = [float(x) for x in to_list(row.get("frame_hz"))]

            ft_str = json.dumps(frame_times)
            fh_str = json.dumps(frame_hz)

            parts = []
            for fn in fieldnames:
                if fn == "frame_times":
                    parts.append(f"\"{ft_str}\"")
                elif fn == "frame_hz":
                    parts.append(f"\"{fh_str}\"")
                else:
                    parts.append(to_scalar(row[fn]))
            f.write(",".join(parts) + "\n")


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

    all_rows = collect_note_rows(args.audio_paths, fmin=args.fmin, fmax=args.fmax, verbose=True)

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
    write_rows(all_rows, args.output_csv, fieldnames)


if __name__ == "__main__":
    main()
