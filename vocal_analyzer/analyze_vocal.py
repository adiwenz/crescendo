#!/usr/bin/env python3
"""
analyze_vocal.py

Compare a vocal WAV against a reference WAV by:
1) Estimating pitch (f0) for both
2) Quantizing the reference to the nearest MIDI note per frame (handles connected legato)
3) Computing frame-aligned cents error between vocal and reference
4) Writing a JSON report consumable by the HTML viewer

Usage:
  python analyze_vocal.py --vocal audio/vocal.wav --reference audio/reference.wav --output_json analysis_similarity.json
"""

import argparse
import json
import os

import librosa
import numpy as np
import pretty_midi


def hz_to_midi_safe(f):
    f = np.asarray(f)
    midi = np.full_like(f, np.nan, dtype=float)
    mask = f > 0
    midi[mask] = 69 + 12 * np.log2(f[mask] / 440.0)
    return midi


def median_filter_1d(x, win=3):
    """Simple 1D median filter (edge-padded)."""
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


def extract_pitch(y, sr, fmin=80.0, fmax=1000.0, frame_length=2048, hop_length=256, median_win=3):
    f0 = librosa.yin(
        y,
        fmin=fmin,
        fmax=fmax,
        sr=sr,
        frame_length=frame_length,
        hop_length=hop_length,
    )
    # optional small median smoothing to reduce jitter
    f0 = median_filter_1d(f0, win=median_win)
    times = librosa.frames_to_time(np.arange(len(f0)), sr=sr, hop_length=hop_length)
    return f0, times


def cents_error(vocal_hz, ref_hz):
    vocal_hz = np.asarray(vocal_hz)
    ref_hz = np.asarray(ref_hz)
    err = np.full_like(vocal_hz, np.nan, dtype=float)
    mask = (vocal_hz > 0) & (ref_hz > 0)
    err[mask] = 1200 * np.log2(vocal_hz[mask] / ref_hz[mask])
    return err


def align_arrays(a, b):
    n = min(len(a), len(b))
    return a[:n], b[:n]


def summarize_errors(cents):
    valid = ~np.isnan(cents)
    if not np.any(valid):
        return {
            "mean_abs_cents": None,
            "pct_within_25": None,
            "pct_within_50": None,
            "pct_within_100": None,
            "valid_frames": 0,
        }
    ce = cents[valid]
    return {
        "mean_abs_cents": float(np.mean(np.abs(ce))),
        "pct_within_25": float(np.mean(np.abs(ce) <= 25) * 100.0),
        "pct_within_50": float(np.mean(np.abs(ce) <= 50) * 100.0),
        "pct_within_100": float(np.mean(np.abs(ce) <= 100) * 100.0),
        "valid_frames": int(len(ce)),
    }


def parse_args():
    ap = argparse.ArgumentParser(description="Compare vocal WAV to reference WAV via nearest-MIDI reference.")
    ap.add_argument("--vocal", required=True, help="Vocal WAV file")
    ap.add_argument("--reference", required=True, help="Reference WAV file")
    ap.add_argument("--output_json", default="analysis_similarity.json", help="Output JSON report")
    ap.add_argument("--fmin", type=float, default=80.0)
    ap.add_argument("--fmax", type=float, default=1000.0)
    ap.add_argument("--frame_length", type=int, default=2048)
    ap.add_argument("--hop_length", type=int, default=256)
    ap.add_argument("--median_win", type=int, default=3, help="Median filter window (frames)")
    return ap.parse_args()


def main():
    args = parse_args()

    print("Loading vocal...")
    vocal_y, vocal_sr = librosa.load(args.vocal, sr=None, mono=True)
    print("Loading reference...")
    ref_y, ref_sr = librosa.load(args.reference, sr=None, mono=True)

    if vocal_sr != ref_sr:
        raise ValueError(f"Sample rate mismatch (vocal {vocal_sr}, reference {ref_sr}); please resample.")

    print("Extracting vocal pitch...")
    vocal_f0, vocal_times = extract_pitch(
        vocal_y,
        vocal_sr,
        fmin=args.fmin,
        fmax=args.fmax,
        frame_length=args.frame_length,
        hop_length=args.hop_length,
        median_win=args.median_win,
    )

    print("Extracting reference pitch...")
    ref_f0, ref_times = extract_pitch(
        ref_y,
        ref_sr,
        fmin=args.fmin,
        fmax=args.fmax,
        frame_length=args.frame_length,
        hop_length=args.hop_length,
        median_win=args.median_win,
    )

    # Align frames (assumes same hop / frame count roughly; truncate to min)
    vocal_f0, ref_f0 = align_arrays(vocal_f0, ref_f0)
    vocal_times, ref_times = align_arrays(vocal_times, ref_times)

    ref_midi_nearest = np.round(hz_to_midi_safe(ref_f0))
    ref_target_hz = pretty_midi.note_number_to_hz(ref_midi_nearest)

    ce = cents_error(vocal_f0, ref_target_hz)
    summary = summarize_errors(ce)

    print("\nSimilarity Summary:")
    print(summary)

    result = {
        "metadata": {
            "vocal_path": args.vocal,
            "reference_path": args.reference,
            "sample_rate": vocal_sr,
            "duration_vocal": len(vocal_y) / vocal_sr,
            "duration_reference": len(ref_y) / ref_sr,
            "frame_length": args.frame_length,
            "hop_length": args.hop_length,
            "fmin": args.fmin,
            "fmax": args.fmax,
            "median_win": args.median_win,
        },
        "summary": summary,
        "frames": [
            {
                "time": float(t),
                "vocal_hz": float(vh),
                "vocal_midi": float(vm) if not np.isnan(vm := hz_to_midi_safe(vh)) else None,
                "ref_hz": float(rh),
                "ref_midi": int(rm) if not np.isnan(rm := ref_midi_nearest[i]) else None,
                "cents_error": float(ce[i]) if not np.isnan(ce[i]) else None,
            }
            for i, (t, vh, rh) in enumerate(zip(vocal_times, vocal_f0, ref_target_hz))
        ],
    }

    if args.output_json:
        with open(args.output_json, "w") as f:
            json.dump(result, f, indent=2)
        print(f"\nWrote JSON to {args.output_json}")


if __name__ == "__main__":
    main()
