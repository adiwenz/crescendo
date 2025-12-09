#!/usr/bin/env python3
"""
Run analyze_vocal for a vocal/reference pair and update a multi-take analysis_similarity.json.

Usage:
  python vocal_analyzer/update_analysis_similarity.py --vocal audio_files/take.wav --reference audio_files/ref.wav --take_name TAKE1 [--json_out vocal_analyzer/analysis_similarity.json]

- Uses analyze_vocal.py to compute the report.
- Stores/updates an entry in a shared JSON with shape: {"runs": [ {take, metadata, summary, frames} ] }
- If an old single-run file is found, it will be wrapped into runs[] and preserved.
"""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Guard against Python 2
import sys
if sys.version_info[0] < 3:
    raise SystemExit("This script requires Python 3. Run with python3.")


def run_analyze(vocal: Path, reference: Path, tmp_out: Path):
    cmd = [
        "python3",
        str(ROOT / "vocal_analyzer" / "analyze_vocal.py"),
        "--vocal",
        str(vocal),
        "--reference",
        str(reference),
        "--output_json",
        str(tmp_out),
    ]
    if args_global.trim_start:
        cmd += ["--trim_start", str(args_global.trim_start)]
    if args_global.trim_end:
        cmd += ["--trim_end", str(args_global.trim_end)]
    if args_global.rms_gate_ratio is not None:
        cmd += ["--rms_gate_ratio", str(args_global.rms_gate_ratio)]
    if args_global.jump_gate_cents is not None:
        cmd += ["--jump_gate_cents", str(args_global.jump_gate_cents)]
    if args_global.score_max_abs_cents is not None:
        cmd += ["--score_max_abs_cents", str(args_global.score_max_abs_cents)]
    subprocess.run(cmd, check=True, cwd=ROOT)


def load_existing(path: Path):
    if not path.exists():
        return {"runs": []}
    with open(path, "r") as f:
        data = json.load(f)
    # normalize to runs list
    if "runs" in data:
        return data
    # legacy single-run file
    return {"runs": [data]}


def rel_to_dashboard(path: Path) -> str:
    # Dashboard lives in vocal_analyzer/, so go up one to repo root then into audio_files
    try:
        return f"../audio_files/{path.name}"
    except Exception:
        return str(path)


def upsert_run(data: dict, take: str, run: dict, vocal_path: Path, ref_path: Path):
    run["take"] = take
    # normalize metadata paths relative to dashboard location (vocal_analyzer/)
    meta = run.get("metadata", {})
    meta["vocal_path"] = rel_to_dashboard(vocal_path)
    meta["reference_path"] = rel_to_dashboard(ref_path)
    run["metadata"] = meta

    runs = data.get("runs", [])
    for i, existing in enumerate(runs):
        if existing.get("take") == take:
            runs[i] = run
            break
    else:
        runs.append(run)
    data["runs"] = runs
    return data


def parse_args():
    ap = argparse.ArgumentParser(description="Update multi-take analysis_similarity.json")
    ap.add_argument("--vocal", required=True, help="Path to vocal WAV")
    ap.add_argument("--reference", required=True, help="Path to reference WAV")
    ap.add_argument("--take_name", required=True, help="Name for this take entry")
    ap.add_argument("--json_out", default=str(ROOT / "vocal_analyzer" / "analysis_similarity.json"))
    ap.add_argument("--trim_start", type=float, default=0.0, help="Seconds to trim from start of both files")
    ap.add_argument("--trim_end", type=float, default=0.0, help="Seconds to trim from end of both files")
    ap.add_argument("--rms_gate_ratio", type=float, default=None, help="Ignore frames with RMS below ratio * max RMS")
    ap.add_argument("--jump_gate_cents", type=float, default=None, help="Ignore frames with |delta| above this cents")
    ap.add_argument("--score_max_abs_cents", type=float, default=None, help="Ignore frames beyond this |cents| for scoring (0 disables)")
    return ap.parse_args()


def main():
    global args_global
    args_global = parse_args()
    vocal = Path(args_global.vocal)
    reference = Path(args_global.reference)
    out_path = Path(args_global.json_out)

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_path = Path(tmp.name)
    tmp.close()

    run_analyze(vocal, reference, tmp_path)

    with open(tmp_path, "r") as f:
        run = json.load(f)

    data = load_existing(out_path)
    data = upsert_run(data, args_global.take_name, run, vocal, reference)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w") as f:
        json.dump(data, f, indent=2)

    print(f"Updated {out_path} with take '{args_global.take_name}'")


if __name__ == "__main__":
    main()
