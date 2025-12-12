#!/usr/bin/env python3
"""Shared pitch estimation and note utilities."""

import csv
import json
from pathlib import Path
from typing import List, Dict, Any, Optional

import numpy as np
import librosa


def median_filter_1d(x, win=3):
    """Apply 1D median filter with odd window; no-op when window <2."""
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


def estimate_pitch_yin(y, sr, fmin=80.0, fmax=1000.0, frame_length=2048, hop_length=256, median_win=3):
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


def estimate_pitch_pyin(y, sr, fmin=80.0, fmax=1000.0, frame_length=2048, hop_length=256, median_win=None):
    """Estimate f0 with PYIN. Returns (f0, times, voiced_flag). Median smoothing optional."""
    f0, voiced_flag, _ = librosa.pyin(
        y,
        fmin=fmin,
        fmax=fmax,
        frame_length=frame_length,
        hop_length=hop_length,
    )
    if median_win and median_win > 1:
        f0 = median_filter_1d(f0, win=median_win)
    times = librosa.frames_to_time(np.arange(len(f0)), sr=sr, hop_length=hop_length)
    return f0, times, voiced_flag


def compute_pitch_accuracy_score(summary: Dict[str, Any]) -> Optional[float]:
    """
    Derive a 0–100 pitch accuracy score from a similarity summary.
    Prefers explicit in-tune proportions if available; otherwise falls back to mean abs cents error.
    Prioritize within-50-cents accuracy as the local pitch score.
    """
    # NOTE: using 50% instead of 25% accuracy
    for key in ("p_within_50_cents", "p_within_25_cents", "percent_in_tune", "pct_within_50", "pct_within_25"):
        val = summary.get(key)
        if val is None:
            continue
        try:
            return round(float(val) * (100.0 if float(val) <= 1 else 1.0), 2)
        except (TypeError, ValueError):
            continue

    mac = summary.get("mean_abs_cents")
    if mac is not None:
        try:
            mac = float(mac)
        except (TypeError, ValueError):
            return None
        raw = 100.0 - mac
        return max(0.0, min(100.0, round(raw, 2)))

    return None


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


def _segment_notes_by_voicing(times: np.ndarray, f0: np.ndarray, voiced_mask: np.ndarray, max_gap_sec: float = 0.08, max_jump_cents: float = 80.0):
    """Segment voiced frames into notes using time gaps and instantaneous pitch jumps."""
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

    boundaries.append((start_idx, len(voiced_times) - 1))
    return voiced_times, voiced_f0, boundaries


def analyze_take(path: str, fmin: float = 80.0, fmax: float = 1000.0, frame_length: int = 2048, hop_length: int = 256, max_gap_sec: float = 0.08, max_jump_cents: float = 80.0, verbose: bool = False) -> List[Dict[str, Any]]:
    """
    Analyze one audio file with PYIN and return a list of note dicts (with frame arrays).
    Mirrors the previous vocal_notes_to_csv implementation so it can be reused elsewhere.
    """
    if verbose:
        print(f"\n=== Analyzing {path} ===")
    y, sr = librosa.load(path, sr=None, mono=True)

    if verbose:
        duration = len(y) / sr
        print(f"Sample rate: {sr} Hz, duration: {duration:.2f} s")

    if verbose:
        print("Estimating pitch (pyin)...")
    f0, _, voiced_flag = estimate_pitch_pyin(
        y,
        sr,
        fmin=fmin,
        fmax=fmax,
        frame_length=frame_length,
        hop_length=hop_length,
    )

    times = librosa.frames_to_time(np.arange(len(f0)), sr=sr, hop_length=hop_length)
    voiced_mask = (~np.isnan(f0)) & (voiced_flag.astype(bool))

    if not np.any(voiced_mask):
        if verbose:
            print("No voiced frames detected.")
        return []

    vt, vf0, note_bounds = _segment_notes_by_voicing(times, f0, voiced_mask, max_gap_sec=max_gap_sec, max_jump_cents=max_jump_cents)
    if not note_bounds:
        if verbose:
            print("No note segments found.")
        return []

    notes_data: List[Dict[str, Any]] = []
    for note_idx, (start_i, end_i) in enumerate(note_bounds):
        note_times = vt[start_i : end_i + 1]
        note_f0 = vf0[start_i : end_i + 1]
        if note_f0.size == 0:
            continue

        mean_f0 = float(np.mean(note_f0))
        midi = float(librosa.hz_to_midi(mean_f0))
        midi_rounded = int(np.round(midi))
        target_hz = float(librosa.midi_to_hz(midi_rounded))
        note_name = librosa.midi_to_note(midi_rounded)
        cents_err = 1200.0 * np.log2(mean_f0 / target_hz)
        start_time = float(note_times[0])
        end_time = float(note_times[-1])
        duration_sec = end_time - start_time

        notes_data.append(
            {
                "note_index": note_idx,
                "start_time": start_time,
                "end_time": end_time,
                "duration": duration_sec,
                "note_name": note_name,
                "measured_hz": mean_f0,
                "target_hz": target_hz,
                "cents_error": cents_err,
                "frame_times": [float(t) for t in note_times.tolist()],
                "frame_hz": [float(hz) for hz in note_f0.tolist()],
            }
        )

    if verbose:
        cents_values = np.array([n["cents_error"] for n in notes_data])
        avg_abs = float(np.mean(np.abs(cents_values))) if cents_values.size else 0.0
        avg_signed = float(np.mean(cents_values)) if cents_values.size else 0.0
        print(f"Notes found: {len(notes_data)}")
        print(f"Average absolute cents error: {avg_abs:.2f}")
        tendency = "neutral"
        if avg_signed < 0:
            tendency = "flat"
        elif avg_signed > 0:
            tendency = "sharp"
        print(f"Average signed cents error:  {avg_signed:.2f} ({tendency})")

    return notes_data


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
