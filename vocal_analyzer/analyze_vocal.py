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


def summarize_errors(cents, max_abs=None):
    valid = ~np.isnan(cents)
    if max_abs is not None:
        valid = valid & (np.abs(cents) <= max_abs)
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
    ap.add_argument("--jump_gate_cents", type=float, default=0.0, help="Ignore frames with > this cents jump vs previous voiced frame (0 disables)")
    ap.add_argument("--rms_gate_ratio", type=float, default=0.0, help="Ignore frames with RMS < ratio * max RMS (0 disables)")
    ap.add_argument("--trim_start", type=float, default=0.0, help="Seconds to trim from start of both files")
    ap.add_argument("--trim_end", type=float, default=0.0, help="Seconds to trim from end of both files")
    ap.add_argument("--score_max_abs_cents", type=float, default=300.0, help="Ignore frames beyond this |cents| for scoring (keeps chart data intact)")
    ap.add_argument("--ignore_short_outliers_ms", type=float, default=120.0, help="If score_max_abs_cents is set, ignore outlier runs shorter than this duration (ms). Set 0 to disable.")
    return ap.parse_args()


def trim_audio(y, sr, trim_start=0.0, trim_end=0.0):
    """Trim leading/trailing seconds; non-destructive if values are 0 or negative."""
    n = len(y)
    start_samp = int(max(0.0, trim_start) * sr)
    end_samp = n - int(max(0.0, trim_end) * sr)
    end_samp = max(start_samp, end_samp)
    return y[start_samp:end_samp]


def gate_frames(f0, rms, rms_gate_ratio=0.02, jump_gate_cents=200.0):
    """Return a mask of frames to keep based on RMS and jump gating."""
    import numpy as np
    keep = np.ones_like(f0, dtype=bool)
    if rms is not None and rms_gate_ratio and rms_gate_ratio > 0:
        max_rms = np.max(rms) if rms.size else 0
        if max_rms > 0:
            keep &= rms >= (rms_gate_ratio * max_rms)
    prev = None
    for i, v in enumerate(f0):
        if np.isnan(v) or v <= 0:
            keep[i] = False
            continue
        if prev is not None and np.isfinite(prev) and jump_gate_cents and jump_gate_cents > 0:
            jump = 1200 * np.log2(v / prev)
            if abs(jump) > jump_gate_cents:
                keep[i] = False
                continue
        prev = v
    return keep


def none_if_nan(x):
    try:
        return None if np.isnan(x) else float(x)
    except Exception:
        return float(x) if x is not None else None


def main():
    args = parse_args()

    print("Loading vocal...")
    vocal_y, vocal_sr = librosa.load(args.vocal, sr=None, mono=True)
    print("Loading reference...")
    ref_y, ref_sr = librosa.load(args.reference, sr=None, mono=True)

    if vocal_sr != ref_sr:
        raise ValueError(f"Sample rate mismatch (vocal {vocal_sr}, reference {ref_sr}); please resample.")

    # Optional trimming to drop noisy sections (e.g., intake breaths/clicks)
    if args.trim_start > 0 or args.trim_end > 0:
        vocal_y = trim_audio(vocal_y, vocal_sr, args.trim_start, args.trim_end)
        ref_y = trim_audio(ref_y, ref_sr, args.trim_start, args.trim_end)

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
    vocal_rms = librosa.feature.rms(y=vocal_y, frame_length=args.frame_length, hop_length=args.hop_length, center=True)[0]

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

    # Apply gating to remove outlier / low-RMS frames
    keep_mask = gate_frames(vocal_f0, vocal_rms, rms_gate_ratio=args.rms_gate_ratio, jump_gate_cents=args.jump_gate_cents)
    vocal_f0 = np.where(keep_mask, vocal_f0, np.nan)

    ce = cents_error(vocal_f0, ref_target_hz)
    summary = summarize_errors(ce, max_abs=args.score_max_abs_cents if args.score_max_abs_cents > 0 else None)

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
            "trim_start": args.trim_start,
            "trim_end": args.trim_end,
            "rms_gate_ratio": args.rms_gate_ratio,
            "jump_gate_cents": args.jump_gate_cents,
        },
        "summary": summary,
        "frames": [
            {
                "time": float(t),
                "vocal_hz": none_if_nan(vh),
                "vocal_midi": none_if_nan(hz_to_midi_safe(vh)),
                "ref_hz": none_if_nan(rh),
                "ref_midi": int(rm) if not np.isnan(rm := ref_midi_nearest[i]) else None,
                "cents_error": none_if_nan(ce[i]),
            }
            for i, (t, vh, rh) in enumerate(zip(vocal_times, vocal_f0, ref_target_hz))
        ],
    }

    if args.output_json:
        with open(args.output_json, "w") as f:
            json.dump(result, f, indent=2, allow_nan=False)
        print(f"\nWrote JSON to {args.output_json}")


if __name__ == "__main__":
    main()
