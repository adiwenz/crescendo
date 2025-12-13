#!/usr/bin/env python3
import json
import os
import tempfile
from pathlib import Path
from typing import List, Optional, Tuple

from flask import Flask, jsonify, request, send_from_directory
import librosa
import numpy as np
import soundfile as sf

# Ensure repo root on sys.path for dutils imports
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.append(str(ROOT))

from dutils.pitch_utils import estimate_pitch_pyin, estimate_pitch_yin, compute_pitch_accuracy_score  # noqa: E402
from dutils.analysis_utils import cents_error, gate_frames  # noqa: E402

APP_DIR = Path(__file__).resolve().parent
STATIC_DIR = APP_DIR / "static"
DATA_DIR = APP_DIR / "data"
TAKES_JSON = DATA_DIR / "takes.json"

app = Flask(__name__, static_folder=str(STATIC_DIR))


WARMUPS = [
    {
        "id": "c_scale_legato",
        "name": "C4–C5 scale (0.5s each, 0.1s gap)",
        "notes": ["C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5"],
        "durations": 0.5,
        "gap": 0.1,
    },
    {
        "id": "c_scale_staccato",
        "name": "C4–C5 staccato (0.25s each, 0.15s gap)",
        "notes": ["C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5"],
        "durations": 0.25,
        "gap": 0.15,
    },
    {
        "id": "c_slide",
        "name": "Slide C4 → G4 → C4 (2s total)",
        "notes": ["C4", "G4", "C4"],
        "durations": [0.8, 0.8, 0.4],
        "gap": 0.0,
    },
]


def midi_from_note(name: str) -> int:
    """Convert note name (e.g., C4) to MIDI integer."""
    return int(round(librosa.note_to_midi(name)))


def build_reference_timeline(
    times: np.ndarray,
    notes: List[str],
    durations: Optional[List[float]] = None,
    gap: float = 0.0,
) -> np.ndarray:
    """Return target Hz per frame based on note list + durations and optional gaps."""
    if durations is None:
        durations = [0.5] * len(notes)
    if isinstance(durations, (float, int)):
        durations = [float(durations)] * len(notes)
    durations = list(durations)
    hz_track = np.full_like(times, np.nan, dtype=float)
    cursor = 0.0
    for note, dur in zip(notes, durations):
        target_hz = float(librosa.note_to_hz(note))
        start = cursor
        end = cursor + dur
        mask = (times >= start) & (times < end)
        hz_track[mask] = target_hz
        cursor = end + gap
    return hz_track


def compute_summary(
    times: np.ndarray,
    f0: np.ndarray,
    target_hz: np.ndarray,
    rms: Optional[np.ndarray] = None,
    rms_gate_ratio: float = 0.0,
) -> Tuple[dict, List[dict]]:
    """Compute cents error vs target Hz with optional RMS gating."""
    min_len_candidates = [len(times), len(f0), len(target_hz)]
    if rms is not None:
        min_len_candidates.append(len(rms))
    min_len = min(min_len_candidates)
    times = times[:min_len]
    f0 = f0[:min_len]
    target_hz = target_hz[:min_len]
    if rms is not None:
        rms = rms[:min_len]

    keep_mask = gate_frames(f0, rms if rms is not None else None, rms_gate_ratio=rms_gate_ratio, jump_gate_cents=0.0)
    f0 = np.where(keep_mask, f0, np.nan)
    target_hz = np.where(keep_mask, target_hz, np.nan)

    cents = cents_error(f0, target_hz)
    valid = np.isfinite(cents)
    abs_cents = np.abs(cents[valid]) if np.any(valid) else np.array([])
    summary = {
        "mean_abs_cents": float(np.mean(abs_cents)) if abs_cents.size else None,
        "pct_within_50": float(np.mean(abs_cents <= 50.0)) if abs_cents.size else None,
        "valid_frames": int(abs_cents.size),
    }
    summary["pitch_accuracy_score"] = compute_pitch_accuracy_score(summary)
    frames = []
    midi = librosa.hz_to_midi(f0)
    target_midi = librosa.hz_to_midi(target_hz)
    for t, hz, thz, m, tm, c in zip(times, f0, target_hz, midi, target_midi, cents):
        frames.append(
            {
                "time": float(t),
                "hz": None if np.isnan(hz) or hz <= 0 else float(hz),
                "midi": None if np.isnan(m) else float(m),
                "target_hz": None if np.isnan(thz) or thz <= 0 else float(thz),
                "target_midi": None if np.isnan(tm) else float(tm),
                "cents_error": None if np.isnan(c) else float(c),
            }
        )
    return summary, frames


def save_take(name: str, summary: dict, frames: List[dict]):
    """Append a lightweight take summary to data/takes.json for history."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    data = {"takes": []}
    if TAKES_JSON.exists():
        try:
            data = json.loads(TAKES_JSON.read_text())
        except Exception:
            data = {"takes": []}
    data.setdefault("takes", [])
    data["takes"].append({"name": name, "summary": summary})
    TAKES_JSON.write_text(json.dumps(data, indent=2))


@app.route("/")
def index():
    """Serve the SPA."""
    return send_from_directory(STATIC_DIR, "index.html")


@app.route("/api/warmups")
def api_warmups():
    """Return built-in warmup presets."""
    return jsonify({"warmups": WARMUPS})


@app.route("/api/takes")
def api_takes():
    """Return previously saved take summaries."""
    if TAKES_JSON.exists():
        try:
            data = json.loads(TAKES_JSON.read_text())
        except Exception:
            data = {"takes": []}
    else:
        data = {"takes": []}
    return jsonify(data)


@app.route("/api/analyze", methods=["POST"])
def api_analyze():
    """Receive audio, run PYIN, compare to reference timeline (warmup/piano), and return frames/summary."""
    if "audio" not in request.files:
        return jsonify({"error": "No audio file provided"}), 400

    audio_file = request.files["audio"]
    name = request.form.get("name") or audio_file.filename or "take"

    use_reference = (request.form.get("use_reference", "true") or "true").lower() not in ("false", "0", "no", "off")

    # Parse reference info
    ref_notes = request.form.get("ref_notes") if use_reference else None
    ref_durations = request.form.get("ref_durations") if use_reference else None
    ref_gap = float(request.form.get("ref_gap", "0.0") or 0.0) if use_reference else 0.0

    # Pitch estimator settings (match pipeline defaults to avoid octave inconsistencies)
    pitch_method = (request.form.get("pitch_method") or "yin").lower()
    # pitch_method = "pyin"
    fmin = float(request.form.get("fmin", "80") or 80.0)
    fmax = float(request.form.get("fmax", "1000") or 1000.0)
    frame_length = int(request.form.get("frame_length", "2048") or 2048)
    hop_length = int(request.form.get("hop_length", "256") or 256)
    median_win = int(request.form.get("median_win", "3") or 3)
    rms_gate_ratio = float(request.form.get("rms_gate_ratio", "0.02") or 0.02)

    if ref_notes:
        try:
            ref_notes = json.loads(ref_notes)
        except Exception:
            ref_notes = None
    if ref_durations:
        try:
            ref_durations = json.loads(ref_durations)
        except Exception:
            ref_durations = None

    with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as tmp:
        tmp_path = Path(tmp.name)
        audio_file.save(tmp_path)

    try:
        y, sr = librosa.load(tmp_path, sr=None, mono=True)
        vocal_rms = librosa.feature.rms(y=y, frame_length=frame_length, hop_length=hop_length, center=True)[0]

        # Match the offline pipeline defaults to reduce octave errors.
        if pitch_method == "pyin":
            f0, times, voiced_flag = estimate_pitch_pyin(
                y,
                sr,
                fmin=fmin,
                fmax=fmax,
                frame_length=frame_length,
                hop_length=hop_length,
                median_win=median_win,
            )
        else:
            f0, times = estimate_pitch_yin(
                y,
                sr,
                fmin=fmin,
                fmax=fmax,
                frame_length=frame_length,
                hop_length=hop_length,
                median_win=median_win,
            )
            # Keep API shape consistent with pYIN

            voiced_flag = np.isfinite(f0)

        print(f"RAW VOCAL F0: {f0}") 
        voiced_mask = (~np.isnan(f0)) & (np.asarray(voiced_flag).astype(bool))
        if not np.any(voiced_mask):
            return jsonify({"error": "No voiced frames detected"}), 400

        if ref_notes:
            target_hz = build_reference_timeline(times, ref_notes, ref_durations, gap=ref_gap)
        else:
            # When no reference is provided, return raw pitch without auto-comparison to rounded MIDI.
            target_hz = np.full_like(times, np.nan, dtype=float)

        summary, frames = compute_summary(
            times,
            f0,
            target_hz,
            rms=vocal_rms,
            rms_gate_ratio=rms_gate_ratio,
        )
        summary["used_reference"] = bool(ref_notes)
        save_take(name, summary, frames)
        return jsonify({"summary": summary, "frames": frames})
    finally:
        try:
            tmp_path.unlink()
        except Exception:
            pass


@app.route("/static/<path:path>")
def serve_static(path):
    return send_from_directory(STATIC_DIR, path)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "5000"))
    app.run(host="0.0.0.0", port=port, debug=True)
