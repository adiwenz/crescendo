#!/usr/bin/env python3
"""
Unified pipeline without subprocesses:
 - Record (optional), with or without reference playback
 - Estimate pitch once and reuse for notes CSV, take CSV, and similarity JSON
 - Rebuild takes_index.json
"""
import argparse
import json
from pathlib import Path

import soundfile as sf

from inter_take_analysis import build_takes_index, record_and_process
from vocal_analyzer.analysis_utils import compute_similarity, load_audio_pair, trim_audio
from vocal_analyzer.volume_analysis_utils import analyze_volume_consistency
from vocal_analyzer.pitch_utils import (
    estimate_pitch,
    write_notes_csv,
    write_take_csv,
    upsert_similarity,
)

ROOT = Path(__file__).resolve().parent
AUDIO_DIR = ROOT / "audio_files"
TAKES_DIR = ROOT / "inter_take_analysis" / "takes"
NOTES_CSV = ROOT / "vocal_notes" / "vocal_notes_stats.csv"
TAKES_INDEX_JSON = ROOT / "inter_take_analysis" / "takes_index.json"
SIM_JSON = ROOT / "vocal_analyzer" / "analysis_similarity.json"


def main():
    ap = argparse.ArgumentParser(description="Unified record/analyze pipeline (no subprocess).")
    ap.add_argument("--take_name", required=True, help="Name for the take")
    ap.add_argument("--reference", help="Reference WAV (optional). If provided, will be played during recording and used for similarity.")
    ap.add_argument("--no_record", action="store_true", help="Skip recording and reuse existing audio_files/<take_name>.wav")
    ap.add_argument("--no_play_reference", action="store_true", help="Do not play the reference while recording (even if provided)")
    ap.add_argument("--samplerate", type=int, default=44100)
    ap.add_argument("--channels", type=int, default=1)
    ap.add_argument("--trim_start", type=float, default=0.0, help="Seconds to trim from start for similarity")
    ap.add_argument("--trim_end", type=float, default=0.0, help="Seconds to trim from end for similarity")
    ap.add_argument("--rms_gate_ratio", type=float, default=0.0, help="RMS gate ratio for similarity (0 disables gating)")
    ap.add_argument("--jump_gate_cents", type=float, default=0.0, help="Jump gate for similarity (0 disables gating)")
    ap.add_argument("--score_max_abs_cents", type=float, default=300.0, help="Ignore frames beyond this |cents| for scoring (0 disables)")
    ap.add_argument("--ignore_short_outliers_ms", type=float, default=120.0, help="If score_max_abs_cents is set, ignore outlier runs shorter than this duration (ms). Set 0 to disable.")
    ap.add_argument("--takes_threshold", type=float, default=25.0, help="Cents threshold for takes_index.json")
    ap.add_argument("--fmin", type=float, default=80.0)
    ap.add_argument("--fmax", type=float, default=1000.0)
    ap.add_argument("--frame_length", type=int, default=2048)
    ap.add_argument("--hop_length", type=int, default=256)
    ap.add_argument("--median_win", type=int, default=3)
    ap.add_argument("--max_delay_ms", type=float, default=0.0, help="Allow up to this delay (ms) when aligning vocal vs reference before scoring.")
    ap.add_argument("--penalize_late_notes", action="store_true", help="If set, do not allow delay compensation (penalize lateness).")
    args = ap.parse_args()

    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    TAKES_DIR.mkdir(parents=True, exist_ok=True)
    NOTES_CSV.parent.mkdir(parents=True, exist_ok=True)

    vocal_wav = AUDIO_DIR / f"{args.take_name}.wav"

    # Record
    if not args.no_record:
        if args.reference and not args.no_play_reference:
            audio, sr = record_and_process.record_with_reference(Path(args.reference), channels=args.channels)
        else:
            audio = record_and_process.record_take(sr=args.samplerate, channels=args.channels)
            sr = args.samplerate
        sf.write(vocal_wav, audio, sr)
        print(f"Wrote {vocal_wav} ({len(audio)/sr:.2f}s)")
    else:
        if not vocal_wav.exists():
            raise FileNotFoundError(f"{vocal_wav} not found and --no_record set.")
        sr = args.samplerate  # assume

    # Load audio
    vocal_y, vocal_sr, ref_y, ref_sr, ref_path = load_audio_pair(
        vocal_path=vocal_wav,
        reference_path=Path(args.reference) if args.reference else None,
        alt_ref_dir=AUDIO_DIR,
    )

    # Trim
    if args.trim_start > 0 or args.trim_end > 0:
        vocal_y = trim_audio(vocal_y, vocal_sr, args.trim_start, args.trim_end)
        if ref_y is not None:
            ref_y = trim_audio(ref_y, ref_sr, args.trim_start, args.trim_end)

    # Pitch once
    vocal_f0_raw, vocal_times = estimate_pitch(
        vocal_y,
        vocal_sr,
        fmin=args.fmin,
        fmax=args.fmax,
        frame_length=args.frame_length,
        hop_length=args.hop_length,
        median_win=args.median_win,
    )

    ref_f0 = None
    ref_times = None
    if ref_y is not None:
        ref_f0, ref_times = estimate_pitch(
            ref_y,
            ref_sr,
            fmin=args.fmin,
            fmax=args.fmax,
            frame_length=args.frame_length,
            hop_length=args.hop_length,
            median_win=args.median_win,
        )

    # Volume consistency (always computed on vocal take)
    volume_summary, volume_frames = analyze_volume_consistency(
        vocal_y,
        vocal_sr,
        frame_length=args.frame_length,
        hop_length=args.hop_length,
    )

    # Similarity if reference provided
    if ref_f0 is not None:
        summary, frames, offset_info = compute_similarity(
            vocal_y=vocal_y,
            vocal_sr=vocal_sr,
            vocal_f0_raw=vocal_f0_raw,
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
        run = {
            "metadata": {
                "vocal_path": f"../audio_files/{vocal_wav.name}",
                "reference_path": f"../audio_files/{ref_path.name}" if ref_path and ref_path.parent == AUDIO_DIR else (str(ref_path) if ref_path else None),
                "sample_rate": vocal_sr,
                "duration_vocal": len(vocal_y) / vocal_sr,
                "duration_reference": len(ref_y) / ref_sr if ref_y is not None else None,
                "frame_length": args.frame_length,
                "hop_length": args.hop_length,
                "fmin": args.fmin,
                "fmax": args.fmax,
                "median_win": args.median_win,
                "trim_start": args.trim_start,
                "trim_end": args.trim_end,
                "rms_gate_ratio": args.rms_gate_ratio,
                "jump_gate_cents": args.jump_gate_cents,
                "score_max_abs_cents": args.score_max_abs_cents,
                "ignore_short_outliers_ms": args.ignore_short_outliers_ms,
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
        }
        upsert_similarity(run, args.take_name, SIM_JSON)

    # Notes/take CSVs using raw pitch
    write_notes_csv(args.take_name, vocal_times, vocal_f0_raw, NOTES_CSV)
    write_take_csv(args.take_name, vocal_times, vocal_f0_raw, TAKES_DIR / f"{args.take_name}.csv")

    # Rebuild takes index
    labels, scores = build_takes_index.build_index(str(TAKES_DIR), args.takes_threshold)
    TAKES_INDEX_JSON.write_text(json.dumps({"labels": labels, "scores": scores, "threshold_cents": args.takes_threshold}, indent=2))

    print("✅ Pipeline complete.")


if __name__ == "__main__":
    main()
