#!/usr/bin/env python3
"""Shared pitch estimation and note utilities."""

import csv
import json
from pathlib import Path
from typing import List, Dict, Any

import numpy as np
import librosa


def median_filter_1d(x, win=3):
    x = np.asarray(x)
    if win is None or win < 2:
        return x
    if win % 2 == 0:
        win += 1
    pad = win // 2
    xp = np.pad(x, (pad, pad), mode="edge")
    out = np.empty_like(x, dtype=float)
    for i in range(len(x)):
        out[i] = np.median(xp[i:i + win])
    return out


def estimate_pitch(y, sr, fmin=80.0, fmax=1000.0, frame_length=2048, hop_length=256, median_win=3):
    """Estimate f0 with YIN + optional median smoothing. Returns (f0, times)."""
    f0 = librosa.yin(
        y,
        fmin=fmin,
        fmax=fmax,
        sr=sr,
        frame_length=frame_length,
        hop_length=hop_length,
    )
    f0 = median_filter_1d(f0, win=median_win)
    times = librosa.frames_to_time(np.arange(len(f0)), sr=sr, hop_length=hop_length)
    return f0, times


def segment_notes(times: np.ndarray, f0: np.ndarray, min_note_len_frames: int = 3) -> List[Dict[str, Any]]:
    """Segment f0 contour into notes based on MIDI changes."""
    notes: List[Dict[str, Any]] = []
    midi_all = librosa.hz_to_midi(f0)
    current = []
    current_midi = None

    def flush():
        nonlocal current, current_midi
        if len(current) < min_note_len_frames:
            current = []
            current_midi = None
            return
        idxs = np.array(current)
        f0_vals = f0[idxs]
        t_vals = times[idxs]
        midi_vals = midi_all[idxs]
        midi_med = float(np.median(midi_vals))
        midi_round = int(round(midi_med))
        target_hz = float(librosa.midi_to_hz(midi_round))
        measured_hz = float(np.median(f0_vals))
        note_name = librosa.midi_to_note(midi_round, unicode=False)
        notes.append(
            {
                "start_idx": idxs[0],
                "end_idx": idxs[-1],
                "start_time": float(t_vals[0]),
                "end_time": float(t_vals[-1]),
                "duration": float(t_vals[-1] - t_vals[0]),
                "note_name": note_name,
                "measured_hz": measured_hz,
                "target_hz": target_hz,
                "cents_error": 1200.0 * np.log2(measured_hz / target_hz) if measured_hz > 0 and target_hz > 0 else 0.0,
                "midi": midi_round,
            }
        )
        current = []
        current_midi = None

    for i, freq in enumerate(f0):
        if np.isnan(freq) or freq <= 0:
            if current:
                flush()
            continue
        midi_r = int(round(midi_all[i]))
        if not current:
            current = [i]
            current_midi = midi_r
            continue
        if midi_r != current_midi:
            flush()
            current = [i]
            current_midi = midi_r
        else:
            current.append(i)
    if current:
        flush()
    return notes


def write_notes_csv(take_name: str, times: np.ndarray, f0: np.ndarray, out_csv: Path):
    """Append note-level data with frame arrays to a CSV (creates header if needed)."""
    notes = segment_notes(times, f0)
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
    rows = []
    for idx, n in enumerate(notes):
        ft = times[n["start_idx"] : n["end_idx"] + 1]
        fhz = f0[n["start_idx"] : n["end_idx"] + 1]
        rows.append(
            {
                "take": take_name,
                "note_index": idx,
                "start_time": n["start_time"],
                "end_time": n["end_time"],
                "duration": n["duration"],
                "note_name": n["note_name"],
                "measured_hz": n["measured_hz"],
                "target_hz": n["target_hz"],
                "cents_error": n["cents_error"],
                "frame_times": json.dumps([float(x) for x in ft]),
                "frame_hz": json.dumps([float(x) for x in fhz]),
            }
        )
    write_header = not out_csv.exists()
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with out_csv.open("a", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        if write_header:
            writer.writeheader()
        for r in rows:
            writer.writerow(r)


def write_take_csv(take_name: str, times: np.ndarray, f0: np.ndarray, out_csv: Path):
    """Write a simplified take CSV (no frame arrays)."""
    notes = segment_notes(times, f0)
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
    ]
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with out_csv.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for idx, n in enumerate(notes):
            writer.writerow(
                {
                    "take": take_name,
                    "note_index": idx,
                    "start_time": n["start_time"],
                    "end_time": n["end_time"],
                    "duration": n["duration"],
                    "note_name": n["note_name"],
                    "measured_hz": n["measured_hz"],
                    "target_hz": n["target_hz"],
                    "cents_error": n["cents_error"],
                }
            )


def upsert_similarity(run: dict, take: str, sim_json: Path):
    """Insert or replace a run in analysis_similarity.json."""
    data = {"runs": []}
    if sim_json.exists():
        data = json.load(sim_json.open())
    runs = data.get("runs", [])
    run["take"] = take
    for i, r in enumerate(runs):
        if r.get("take") == take:
            runs[i] = run
            break
    else:
        runs.append(run)
    data["runs"] = runs
    sim_json.write_text(json.dumps(data, indent=2, allow_nan=False))
