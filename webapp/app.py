import os
import sys
import warnings
import time
from pathlib import Path
from uuid import uuid4

import numpy as np

BASE_DIR = Path(__file__).resolve().parent
REPO_ROOT = BASE_DIR.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.append(str(REPO_ROOT))

from flask import Flask, jsonify, request, send_from_directory
import librosa
import soundfile as sf
from werkzeug.utils import secure_filename
from vocal_coach.chatgpt_utils import ChatGPTFeedback, get_chatgpt_feedback
from vocal_analyzer.pitch_utils import compute_pitch_accuracy_score, estimate_pitch_pyin, segment_notes

UPLOAD_FOLDER = BASE_DIR / "uploads"

app = Flask(__name__, static_folder=None)
app.config["UPLOAD_FOLDER"] = str(UPLOAD_FOLDER)


def ensure_upload_folder() -> None:
    UPLOAD_FOLDER.mkdir(parents=True, exist_ok=True)


def build_filename(original_name: str) -> str:
    filename = secure_filename(original_name)
    if not filename:
        return f"upload-{uuid4().hex}"
    stem, ext = os.path.splitext(filename)
    return f"{stem}-{uuid4().hex}{ext}"


def compute_pyin_contour(audio_path: Path, target_sr: int = 16000) -> dict:
    """Estimate pitch contour with PYIN and return frames + summary metrics."""
    y, sr = librosa.load(audio_path, sr=target_sr, mono=True)
    f0, voiced_flag, _ = estimate_pitch_pyin(
        y,
        sr=sr,
        fmin=80.0,
        fmax=1000.0,
        frame_length=2048,
        hop_length=256,
        median_win=3,
    )
    hop_length = 256
    times = librosa.frames_to_time(np.arange(len(f0)), sr=sr, hop_length=hop_length)
    frames = []
    cents_errors = []
    for t, hz, voiced in zip(times, f0, voiced_flag):
        if not voiced or hz is None or (isinstance(hz, float) and (hz != hz)) or hz <= 0:  # NaN guard
            continue
        midi = float(librosa.hz_to_midi(hz))
        nearest_midi = round(midi)
        target_hz = librosa.midi_to_hz(nearest_midi)
        cents_err = 1200.0 * np.log2(hz / target_hz) if target_hz > 0 else 0.0
        cents_errors.append(cents_err)
        frames.append(
            {
                "time": float(t),
                "midi": float(midi),
                "cents_error": float(cents_err),
            }
        )

    notes = segment_notes(times, f0)

    summary = {}
    if cents_errors:
        cents_arr = np.asarray(cents_errors, dtype=float)
        summary = {
            "mean_abs_cents": float(np.mean(np.abs(cents_arr))),
            "rms_cents": float(np.sqrt(np.mean(cents_arr ** 2))),
            "pct_within_50": float(np.mean(np.abs(cents_arr) <= 50.0)),  # proportion 0–1
            "valid_frames": int(len(cents_arr)),
        }
        summary["pitch_accuracy_score"] = compute_pitch_accuracy_score(summary)
    return {"frames": frames, "summary": summary, "notes": notes}


@app.route("/", methods=["GET"])
def serve_dashboard():
    return send_from_directory(BASE_DIR, "dashboard.html")


@app.route("/analyze", methods=["POST"])
def analyze():
    ensure_upload_folder()
    file = request.files.get("audio") or request.files.get("file")
    if file is None or file.filename == "":
        return jsonify({"error": "No audio file provided"}), 400

    filename = build_filename(file.filename)
    save_path = UPLOAD_FOLDER / filename
    file.save(save_path)

    chatgpt_audio_path = save_path
    duration_seconds = 0.0
    print("saving to wav")
    preprocess_start = time.time()
    try:
        if save_path.suffix.lower() in {".wav", ".wave"}:
            try:
                duration_seconds = float(sf.info(save_path).duration)
            except Exception:
                # Fallback if SoundFile can't read duration
                duration_seconds = float(librosa.get_duration(path=save_path))
        else:
            # Convert to wav because ChatGPT call expects wav input.
            target_sr = 16000
            with warnings.catch_warnings():
                warnings.filterwarnings("ignore", message="PySoundFile failed*")
                warnings.filterwarnings("ignore", message=".*__audioread_load.*", category=FutureWarning)
                y, sr = librosa.load(save_path, sr=target_sr, mono=True)
            if y is None or sr is None:
                raise ValueError("Audio decode returned empty data")
            wav_path = save_path.with_suffix(".wav")
            sf.write(wav_path, y, target_sr)
            chatgpt_audio_path = wav_path
            duration_seconds = float(librosa.get_duration(y=y, sr=target_sr))
    except Exception as e:
        app.logger.exception("Audio preprocessing failed: %s", e)
        return jsonify({"error": f"Audio preprocessing failed: {e}"}), 500
    preprocess_time = time.time() - preprocess_start
    print(f"converted to wav (or reused) in {preprocess_time:.2f}s")

    # Local PYIN contour used for visualization and as the fixed pitch score.
    pyin_result = {}
    try:
        pyin_result = compute_pyin_contour(chatgpt_audio_path)
    except Exception as e:
        app.logger.exception("PYIN pitch extraction failed: %s", e)

    print("getting chatgpt feedback")
    start_gpt = time.time()
    locked_metrics = None
    if pyin_result and pyin_result.get("summary", {}).get("pitch_accuracy_score") is not None:
        locked_metrics = {"pitch_accuracy": pyin_result["summary"]["pitch_accuracy_score"]}
        local_score = pyin_result["summary"]["pitch_accuracy_score"]
        app.logger.info("Local PYIN pitch_accuracy_score (pct within 50c): %.2f", local_score)
        print(f"Local PYIN pitch_accuracy_score (pct within 50c): {local_score:.2f}")
    try:
        # Previous behavior (kept for reference):
        # chatgpt_feedback: ChatGPTFeedback = get_chatgpt_feedback(
        #     audio_path=chatgpt_audio_path,
        #     analysis_context={"duration": duration_seconds},
        #     return_pitch_contour=True,
        # )
        chatgpt_feedback: ChatGPTFeedback = get_chatgpt_feedback(
            audio_path=chatgpt_audio_path,
            analysis_context={"duration": duration_seconds, "pitch_summary": pyin_result.get("summary")},
            locked_metrics=locked_metrics,
            return_pitch_contour=False,
        )
        chatgpt_raw_text = chatgpt_feedback.raw_text
    except Exception as e:
        app.logger.exception("ChatGPT feedback call crashed: %s", e)
        chatgpt_feedback = get_chatgpt_feedback(audio_path=save_path, mock=True)
        chatgpt_feedback.error = str(e)
        chatgpt_raw_text = chatgpt_feedback.raw_text
    elapsed_gpt = time.time() - start_gpt
    print(f"chatgpt call took {elapsed_gpt:.2f}s")

    chatgpt_error = chatgpt_feedback.error
    if chatgpt_error:
        app.logger.error("ChatGPT feedback error: %s", chatgpt_error)
        if chatgpt_raw_text:
            # Log the raw text returned by ChatGPT to diagnose JSON parsing issues.
            app.logger.error("ChatGPT raw response: %s", chatgpt_raw_text)
        # fall back to mock feedback so UI still renders
        fallback = get_chatgpt_feedback(audio_path=save_path, mock=True)
        fallback.error = chatgpt_error
        # Preserve the raw response that caused the failure for downstream debugging.
        fallback.raw_text = chatgpt_raw_text or fallback.raw_text
        chatgpt_feedback = fallback
    metrics = chatgpt_feedback.metrics or {}
    overall_score = metrics.get("overall_score", {}).get("score") or pyin_result.get("summary", {}).get("pitch_accuracy_score") or 98.0
    pyin_frames = pyin_result.get("frames") if pyin_result else []
    pitch_data = pyin_frames if pyin_frames else (chatgpt_feedback.pitch_contour or [])
    pyin_summary = pyin_result.get("summary", {}) if pyin_result else {}

    take_payload = {
        "name": file.filename or "Uploaded Take",
        "audio_url": f"/uploads/{filename}",
        "pitch_data": pitch_data,
        "frames": pitch_data,
        "score": float(overall_score),
        "score_label": chatgpt_feedback.summary or "AI vocal feedback",
        "mean_error": pyin_summary.get("mean_abs_cents", 0.0),
        "rms_error": pyin_summary.get("rms_cents", 0.0),
        "duration": duration_seconds,
        "local_pitch_accuracy_score": pyin_summary.get("pitch_accuracy_score"),
    }

    response = {
        "take1": take_payload,
        "vocal_take": {
            "label": take_payload["name"],
            "audio_url": take_payload["audio_url"],
            "duration_seconds": duration_seconds,
            "overall_mean_cents_error": pyin_summary.get("mean_abs_cents", 0.0),
            "overall_rms_cents_error": pyin_summary.get("rms_cents", 0.0),
            "accuracy_score": pyin_summary.get("pitch_accuracy_score", overall_score),
            "frames": pitch_data,
            "local_pitch_accuracy_score": pyin_summary.get("pitch_accuracy_score"),
        },
        "chatgpt_feedback": chatgpt_feedback.to_dict(),
        **({"chatgpt_raw_response": chatgpt_raw_text} if chatgpt_error and chatgpt_raw_text else {}),
        **({"chatgpt_error": chatgpt_error} if chatgpt_error else {}),
    }
    return jsonify(response)


@app.route("/uploads/<path:filename>", methods=["GET"])
def serve_upload(filename):
    ensure_upload_folder()
    return send_from_directory(app.config["UPLOAD_FOLDER"], filename)


if __name__ == "__main__":
    ensure_upload_folder()
    app.run(debug=True)
