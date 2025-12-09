#!/usr/bin/env python3
"""
Unified pipeline to:
1) Record a take (optional, press SPACE to stop; or play a reference while recording)
2) Append note stats to vocal_notes/vocal_notes_stats.csv
3) Generate per-take CSV (inter_take_analysis/takes/<take>.csv)
4) Rebuild takes_index.json
5) (Optional) Run similarity vs reference and update analysis_similarity.json

This replaces the chained shell scripts with one entry point.
"""
import argparse
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

import soundfile as sf

# Local imports
from inter_take_analysis import generate_take
from inter_take_analysis import build_takes_index
from inter_take_analysis import record_and_process

ROOT = Path(__file__).resolve().parent
AUDIO_DIR = ROOT / "audio_files"
TAKES_DIR = ROOT / "inter_take_analysis" / "takes"
NOTES_CSV = ROOT / "vocal_notes" / "vocal_notes_stats.csv"
TAKES_INDEX_JSON = ROOT / "inter_take_analysis" / "takes_index.json"
SIM_JSON = ROOT / "vocal_analyzer" / "analysis_similarity.json"


def append_vocal_notes(wav_path: Path):
    """Run vocal_notes_to_csv on a single file and append rows to the main CSV."""
    tmp = Path(tempfile.mktemp(suffix=".csv"))
    try:
        subprocess.run(
            [
                "python3",
                str(ROOT / "vocal_notes" / "vocal_notes_to_csv.py"),
                str(wav_path),
                "--output_csv",
                str(tmp),
            ],
            check=True,
            cwd=ROOT,
        )
        if NOTES_CSV.exists():
            with NOTES_CSV.open("a") as dest, tmp.open("r") as src:
                lines = src.readlines()
                if lines:
                    dest.writelines(lines[1:])  # skip header
        else:
            shutil.move(str(tmp), str(NOTES_CSV))
    finally:
        if tmp.exists():
            tmp.unlink()


def rebuild_takes_index(threshold: float = 25.0, output: Path = TAKES_INDEX_JSON):
    labels, scores = build_takes_index.build_index(str(TAKES_DIR), threshold)
    data = {"labels": labels, "scores": scores, "threshold_cents": threshold}
    output.write_text(json.dumps(data, indent=2))
    return data


def run_similarity(vocal: Path, reference: Path, take: str, trim_start: float, trim_end: float, rms_gate: float, jump_gate: float, score_cap: float, ignore_short_ms: float):
    cmd = [
        "python3",
        str(ROOT / "vocal_analyzer" / "update_analysis_similarity.py"),
        "--vocal",
        str(vocal),
        "--reference",
        str(reference),
        "--take_name",
        take,
        "--trim_start",
        str(trim_start),
        "--trim_end",
        str(trim_end),
        "--rms_gate_ratio",
        str(rms_gate),
        "--jump_gate_cents",
        str(jump_gate),
        "--score_max_abs_cents",
        str(score_cap),
        "--ignore_short_outliers_ms",
        str(ignore_short_ms),
    ]
    subprocess.run(cmd, check=True, cwd=ROOT)


def main():
    ap = argparse.ArgumentParser(description="Unified record/analyze pipeline.")
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
    args = ap.parse_args()

    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    TAKES_DIR.mkdir(parents=True, exist_ok=True)

    vocal_wav = AUDIO_DIR / f"{args.take_name}.wav"

    # 1) Record if requested
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

    # 2) Append note stats (single-take) to CSV
    append_vocal_notes(vocal_wav)

    # 3) Generate per-take CSV
    generate_take.analyze_audio_to_take(
        audio_path=str(vocal_wav),
        take_name=args.take_name,
        output_csv=str(TAKES_DIR / f"{args.take_name}.csv"),
        fmin="C2",
        fmax="C7",
        frame_length=2048,
        hop_length=256,
    )

    # 4) Rebuild takes_index.json
    rebuild_takes_index(args.takes_threshold, TAKES_INDEX_JSON)

    # 5) Similarity (optional)
    if args.reference:
        ref_path = Path(args.reference)
        if not ref_path.exists():
            # try under audio_files
            alt = AUDIO_DIR / ref_path.name
            if alt.exists():
                ref_path = alt
            else:
                raise FileNotFoundError(f"Reference not found: {args.reference}")
        run_similarity(
            vocal_wav,
            ref_path,
            args.take_name,
            args.trim_start,
            args.trim_end,
            args.rms_gate_ratio,
            args.jump_gate_cents,
            args.score_max_abs_cents,
            args.ignore_short_outliers_ms,
        )

    print("✅ Pipeline complete.")


if __name__ == "__main__":
    main()
