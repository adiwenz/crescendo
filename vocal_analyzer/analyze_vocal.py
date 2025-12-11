#!/usr/bin/env python3
"""
analyze_vocal.py

Compare a vocal WAV against a reference WAV by:
1) Estimating pitch (f0) for both using librosa.yin
2) Quantizing the reference to the nearest MIDI note per frame (handles connected legato)
3) Computing frame-aligned cents error between vocal and reference
4) Writing a JSON report consumable by the HTML viewer

Usage:
  python analyze_vocal.py --vocal audio/vocal.wav --reference audio/reference.wav --output_json analysis_similarity.json
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.append(str(ROOT))

from dutils.analysis_utils import compute_similarity, load_audio_pair, trim_audio
from dutils.volume_analysis_utils import analyze_volume_consistency
from dutils.tone_analysis_utils import analyze_tone
from dutils.pitch_utils import estimate_pitch_yin


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
    ap.add_argument("--max_delay_ms", type=float, default=0.0, help="Allow up to this delay (ms) when aligning vocal vs reference before scoring.")
    ap.add_argument("--penalize_late_notes", action="store_true", help="If set, do not allow delay compensation (penalize lateness).")
    ap.add_argument("--tone_metrics", default="smoothness,spectral,jitter", help="Comma-separated tone metrics to compute (smoothness,spectral,jitter).")
    ap.add_argument("--tone_smooth_win", type=int, default=5, help="Window for tone smoothness smoothing (frames).")
    ap.add_argument("--tone_smooth_tol_cents", type=float, default=20.0, help="Tolerance (cents per step) for tone smoothness percent metric.")
    return ap.parse_args()


def main():
    args = parse_args()

    vocal_y, vocal_sr, ref_y, ref_sr, _ = load_audio_pair(Path(args.vocal), Path(args.reference))

    # Optional trimming to drop noisy sections (e.g., intake breaths/clicks)
    if args.trim_start > 0 or args.trim_end > 0:
        vocal_y = trim_audio(vocal_y, vocal_sr, args.trim_start, args.trim_end)
        ref_y = trim_audio(ref_y, ref_sr, args.trim_start, args.trim_end)

    print("Extracting vocal pitch...")
    vocal_f0, vocal_times = estimate_pitch_yin(
        vocal_y,
        vocal_sr,
        fmin=args.fmin,
        fmax=args.fmax,
        frame_length=args.frame_length,
        hop_length=args.hop_length,
        median_win=args.median_win,
    )

    print("Extracting reference pitch...")
    ref_f0, ref_times = estimate_pitch_yin(
        ref_y,
        ref_sr,
        fmin=args.fmin,
        fmax=args.fmax,
        frame_length=args.frame_length,
        hop_length=args.hop_length,
        median_win=args.median_win,
    )

    summary, frames, offset_info = compute_similarity(
        vocal_y=vocal_y,
        vocal_sr=vocal_sr,
        vocal_f0_raw=vocal_f0,
        vocal_times=vocal_times,
        ref_f0=ref_f0,
        ref_times=ref_times,
        frame_length=args.frame_length,
        hop_length=args.hop_length,
        rms_gate_ratio=args.rms_gate_ratio,
        jump_gate_cents=args.jump_gate_cents,
        score_max_abs_cents=args.score_max_abs_cents,
        ignore_short_outliers_ms=args.ignore_short_outliers_ms,
        max_delay_ms=args.max_delay_ms,
        penalize_late=args.penalize_late_notes,
    )

    volume_summary, volume_frames = analyze_volume_consistency(
        vocal_y,
        vocal_sr,
        frame_length=args.frame_length,
        hop_length=args.hop_length,
    )

    tone_metrics = [m.strip() for m in args.tone_metrics.split(",") if m.strip()]
    tone_summary, tone_frames = analyze_tone(
        vocal_y,
        vocal_sr,
        vocal_f0,
        vocal_times,
        frame_length=args.frame_length,
        hop_length=args.hop_length,
        metrics=tone_metrics,
        smooth_win=args.tone_smooth_win,
        smooth_tolerance_cents=args.tone_smooth_tol_cents,
    )

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
            "alignment_offset_frames": offset_info["offset_frames"],
            "alignment_offset_ms": offset_info["offset_ms"],
            "max_delay_ms": args.max_delay_ms,
            "penalize_late_notes": args.penalize_late_notes,
        },
        "summary": summary,
        "frames": frames,
        "volume": {
            "summary": volume_summary,
            "frames": volume_frames,
        },
        "tone": {
            "summary": tone_summary,
            "frames": tone_frames,
            "metrics": tone_metrics,
        },
    }

    if args.output_json:
        with open(args.output_json, "w") as f:
            json.dump(result, f, indent=2, allow_nan=False)
        print(f"\nWrote JSON to {args.output_json}")


if __name__ == "__main__":
    main()
