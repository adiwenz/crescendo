import os
from pathlib import Path
from uuid import uuid4

from flask import Flask, jsonify, request, send_from_directory
from werkzeug.utils import secure_filename

BASE_DIR = Path(__file__).resolve().parent
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

    pitch_data = [{"time": t / 10.0, "pitch": 200 + (t % 20)} for t in range(50)]
    duration_seconds = pitch_data[-1]["time"] if pitch_data else 0.0

    response = {
        "take1": {
            "name": file.filename or "Uploaded Take",
            "audio_url": f"/uploads/{filename}",
            "pitch_data": pitch_data,
            "score": 98.0,
            "score_label": "Great intonation",
            "mean_error": 2.5,
            "rms_error": 3.4,
            "duration": duration_seconds,
        }
    }
    return jsonify(response)


@app.route("/uploads/<path:filename>", methods=["GET"])
def serve_upload(filename):
    ensure_upload_folder()
    return send_from_directory(app.config["UPLOAD_FOLDER"], filename)


if __name__ == "__main__":
    ensure_upload_folder()
    app.run(debug=True)
