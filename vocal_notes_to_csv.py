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
    frame_times   - semicolon-separated timestamps (s) for each voiced frame in the note
    frame_hz      - semicolon-separated f0 estimates (Hz) matching frame_times
"""

import argparse
import csv
import os
from typing import List, Dict, Any

import numpy as np
import librosa


def segment_notes(times: np.ndarray,
                  f0: np.ndarray,
                  voiced_mask: np.ndarray,
                  max_gap_sec: float = 0.08,
                  max_jump_cents: float = 80.0):
    """
    Segment continuous voiced frames into notes.

    Rules:
    - Break if time gap between consecutive voiced frames > max_gap_sec
    - Break if instantaneous pitch jump > max_jump_cents
    Returns:
        (voiced_times, voiced_f0, list_of_(start_idx, end_idx))
        where indices are into the voiced-only arrays.
    """
    voiced_times = times[voiced_mask]
    voiced_f0 = f0[voiced_mask]

    if voiced_times.size == 0:
        return voiced_times, voiced_f0, []

    def cents_between(f1, f2):
        return 1200.0 * np.log2(f1 / f2)

    boundaries = []
    start_idx = 0

    for i in range(1, len(voiced_times)):
        dt = voiced_times[i] - voiced_times[i - 1]
        new_note = False

        if dt > max_gap_sec:
            new_note = True
        else:
            jump_cents = abs(cents_between(voiced_f0[i], voiced_f0[i - 1]))
            if jump_cents > max_jump_cents:
                new_note = True

        if new_note:
            boundaries.append((start_idx, i - 1))
            start_idx = i

    # last note
    boundaries.append((start_idx, len(voiced_times) - 1))

    return voiced_times, voiced_f0, boundaries


def analyze_take(path: str,
                 fmin: float = 80.0,
                 fmax: float = 1000.0,
                 frame_length: int = 2048,
                 hop_length: int = 256) -> List[Dict[str, Any]]:
    """
    Analyze one audio file and return a list of note dicts.
    """
    print(f"\n=== Analyzing {path} ===")
    y, sr = librosa.load(path, sr=None, mono=True)
    duration = len(y) / sr
    print(f"Sample rate: {sr} Hz, duration: {duration:.2f} s")

    # Pitch estimation with pyin
    print("Estimating pitch (pyin)...")
    f0, voiced_flag, voiced_prob = librosa.pyin(
        y,
        fmin=fmin,
        fmax=fmax,
        frame_length=frame_length,
        hop_length=hop_length,
    )

    times = librosa.frames_to_time(
        np.arange(len(f0)), sr=sr, hop_length=hop_length
    )

    # Only consider frames with a valid f0 AND marked as voiced
    voiced_mask = (~np.isnan(f0)) & (voiced_flag.astype(bool))

    if not np.any(voiced_mask):
        print("No voiced frames detected.")
        return []

    vt, vf0, note_bounds = segment_notes(times, f0, voiced_mask)

    if not note_bounds:
        print("No note segments found.")
        return []

    notes_data: List[Dict[str, Any]] = []

    for note_idx, (start_i, end_i) in enumerate(note_bounds):
        # frames for this note (indices into voiced arrays)
        note_times = vt[start_i:end_i + 1]
        note_f0 = vf0[start_i:end_i + 1]

        if note_f0.size == 0:
            continue

        mean_f0 = float(np.mean(note_f0))

        # nearest equal-tempered note
        midi = float(librosa.hz_to_midi(mean_f0))
        midi_rounded = int(np.round(midi))
        target_hz = float(librosa.midi_to_hz(midi_rounded))
        note_name = librosa.midi_to_note(midi_rounded)

        # cents error
        cents_err = 1200.0 * np.log2(mean_f0 / target_hz)

        start_time = float(note_times[0])
        end_time = float(note_times[-1])
        duration_sec = end_time - start_time

        # Keep the raw contour so the UI can draw the curvy performance line
        frame_times = [float(t) for t in note_times.tolist()]
        frame_hz = [float(hz) for hz in note_f0.tolist()]

        notes_data.append({
            "note_index": note_idx,
            "start_time": start_time,
            "end_time": end_time,
            "duration": duration_sec,
            "note_name": note_name,
            "measured_hz": mean_f0,
            "target_hz": target_hz,
            "cents_error": cents_err,
            "frame_times": frame_times,
            "frame_hz": frame_hz,
        })

    # Print quick summary
    cents_values = np.array([n["cents_error"] for n in notes_data])
    avg_abs = float(np.mean(np.abs(cents_values)))
    avg_signed = float(np.mean(cents_values))

    print(f"Notes found: {len(notes_data)}")
    print(f"Average absolute cents error: {avg_abs:.2f}")
    print(f"Average signed cents error:  {avg_signed:.2f} "
          f"({'flat' if avg_signed < 0 else 'sharp' if avg_signed > 0 else 'neutral'})")

    return notes_data


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

    all_rows: List[Dict[str, Any]] = []

    for audio_path in args.audio_paths:
        take_name = os.path.splitext(os.path.basename(audio_path))[0]
        notes = analyze_take(audio_path, fmin=args.fmin, fmax=args.fmax)

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
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in all_rows:
            # Convert arrays to compact semicolon-separated strings for CSV
            row_out = {
                **row,
                "frame_times": ";".join(f"{t:.4f}" for t in row["frame_times"]),
                "frame_hz": ";".join(f"{hz:.3f}" for hz in row["frame_hz"]),
            }
            writer.writerow(row)


if __name__ == "__main__":
    main()
