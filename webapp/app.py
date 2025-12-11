import os
import math
import sys
from pathlib import Path
from uuid import uuid4

BASE_DIR = Path(__file__).resolve().parent
REPO_ROOT = BASE_DIR.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.append(str(REPO_ROOT))

from flask import Flask, jsonify, request, send_from_directory
import librosa
import soundfile as sf
from werkzeug.utils import secure_filename
from vocal_coach.chatgpt_utils import ChatGPTFeedback, get_chatgpt_feedback
from vocal_analyzer.pitch_utils import estimate_pitch_pyin

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

    try:
        y, sr = librosa.load(save_path, sr=None, mono=True)
        # Normalize to WAV for downstream consumers (ChatGPT expects format to match).
        wav_path = save_path.with_suffix(".wav")
        sf.write(wav_path, y, sr)

        f0, times, voiced = estimate_pitch_pyin(y, sr)
        pitch_data = [
            {"time": float(t), "pitch": float(f)}
            for t, f, v in zip(times, f0, voiced)
            if v and f and math.isfinite(f) and f > 0
        ]
        duration_seconds = float(times[-1]) if len(times) else 0.0
        chatgpt_audio_path = wav_path
    except Exception as e:
        pitch_data = []
        duration_seconds = 0.0
        return jsonify({"error": f"Pitch analysis failed: {e}"}), 500

    chatgpt_feedback: ChatGPTFeedback = get_chatgpt_feedback(
        audio_path=chatgpt_audio_path,
        analysis_context={"duration": duration_seconds},
    )
    chatgpt_error = chatgpt_feedback.error
    if chatgpt_error:
        app.logger.error("ChatGPT feedback error: %s", chatgpt_error)
        # fall back to mock feedback so UI still renders
        fallback = get_chatgpt_feedback(audio_path=save_path, mock=True)
        fallback.error = chatgpt_error
        chatgpt_feedback = fallback
    metrics = chatgpt_feedback.metrics or {}
    overall_score = metrics.get("overall_score", {}).get("score") or 98.0

    response = {
        "take1": {
            "name": file.filename or "Uploaded Take",
            "audio_url": f"/uploads/{filename}",
            "pitch_data": pitch_data,
            "score": float(overall_score),
            "score_label": chatgpt_feedback.summary or "AI vocal feedback",
            "mean_error": 2.5,
            "rms_error": 3.4,
            "duration": duration_seconds,
        },
        "chatgpt_feedback": chatgpt_feedback.to_dict(),
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
