# app.py
import os
import math
import json
import uuid
import numpy as np
import soundfile as sf
from flask import Flask, request, render_template_string, send_from_directory, redirect, url_for

# ------------------ Pitch + Segmentation Logic ------------------ #

def pitch_from_autocorr(frame, sr, fmin=60.0, fmax=1600.0):
    """Rough monophonic f0 via autocorrelation (same idea as before)."""
    frame = frame - np.mean(frame)
    if np.allclose(frame, 0):
        return None

    corr = np.correlate(frame, frame, mode="full")
    corr = corr[len(corr)//2:]

    # find first positive slope region
    d = np.diff(corr)
    starts = np.where(d > 0)[0]
    if len(starts) == 0:
        return None
    start = starts[0]

    peak = np.argmax(corr[start:]) + start
    if peak <= 0:
        return None

    f0 = float(sr / peak)
    if f0 < fmin or f0 > fmax:
        return None
    return f0


NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F",
              "F#", "G", "G#", "A", "A#", "B"]

def midi_to_note_name(midi):
    midi = int(round(midi))
    name = NOTE_NAMES[midi % 12]
    octave = midi // 12 - 1
    return f"{name}{octave}"


def analyze_wav(path):
    """Return times, f0s, and segments for given WAV file, plus duration."""
    y, sr = sf.read(path)
    if y.ndim > 1:
        y = y.mean(axis=1)

    frame_size = 2048
    hop = 256

    times = []
    f0s = []

    for i in range(0, len(y) - frame_size, hop):
        frame = y[i:i+frame_size]
        t = i / sr
        f0 = pitch_from_autocorr(frame, sr)
        times.append(float(t))
        f0s.append(None if f0 is None else float(f0))

    times = np.array(times, dtype=float)
    f0s_array = np.array(
        [np.nan if f is None else f for f in f0s],
        dtype=float
    )

    # Build segments by quantized MIDI note
    segments = []
    current = None

    def flush_segment():
        nonlocal current
        if current is None:
            return
        idxs = current["idxs"]
        seg_f0s = f0s_array[idxs]
        seg_f0s = seg_f0s[~np.isnan(seg_f0s)]
        if len(seg_f0s) == 0:
            current = None
            return

        # use nearest MIDI of the segment
        midi_vals = 69 + 12 * np.log2(seg_f0s / 440.0)
        nearest_midi = int(round(np.nanmean(midi_vals)))
        target_hz = 440.0 * (2 ** ((nearest_midi - 69) / 12))
        cents = 1200 * np.log2(seg_f0s / target_hz)
        mean_cents = float(np.nanmean(cents))

        y_min = float(np.nanmin(seg_f0s))
        y_max = float(np.nanmax(seg_f0s))

        # color by intonation
        ac = abs(mean_cents)
        if ac <= 20:
            bg = "rgba(0, 180, 0, 0.35)"
            border = "rgba(0, 220, 0, 0.8)"
        elif ac <= 40:
            bg = "rgba(220, 180, 0, 0.35)"
            border = "rgba(255, 210, 0, 0.9)"
        else:
            bg = "rgba(220, 0, 0, 0.35)"
            border = "rgba(255, 60, 60, 0.95)"

        segments.append({
            "nearest_midi": nearest_midi,
            "start": float(times[idxs[0]]),
            "end": float(times[idxs[-1]]),
            "mean_cents": mean_cents,
            "yMin": y_min,
            "yMax": y_max,
            "note_name": midi_to_note_name(nearest_midi),
            "bgColor": bg,
            "borderColor": border,
        })
        current = None

    # group contiguous frames with same nearest_midi
    for idx, (t, f0) in enumerate(zip(times, f0s_array)):
        if np.isnan(f0):
            flush_segment()
            continue

        midi = 69 + 12 * np.log2(f0 / 440.0)
        nearest_midi = int(round(midi))

        if current is None:
            current = {
                "nearest_midi": nearest_midi,
                "idxs": [idx],
            }
        else:
            if nearest_midi == current["nearest_midi"] and \
               idx == current["idxs"][-1] + 1:
                current["idxs"].append(idx)
            else:
                flush_segment()
                current = {
                    "nearest_midi": nearest_midi,
                    "idxs": [idx],
                }

    flush_segment()

    duration = len(y) / sr

    return list(times), f0s, segments, duration


# ------------------ Flask App ------------------ #

app = Flask(__name__)
UPLOAD_FOLDER = os.path.join(os.path.dirname(__file__), "uploads")
os.makedirs(UPLOAD_FOLDER, exist_ok=True)


@app.route("/uploads/<path:filename>")
def uploaded_file(filename):
    return send_from_directory(UPLOAD_FOLDER, filename)


TEMPLATE = r"""
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Melodyne-Style Pitch Graph</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/chartjs-plugin-annotation@3.0.1/dist/chartjs-plugin-annotation.min.js"></script>
  <style>
    html, body {
      margin: 0;
      padding: 0;
      height: 100%;
      width: 100%;
      background: #0c0c0f;
      color: #eee;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    #app {
      display: flex;
      flex-direction: column;
      height: 100vh;
      width: 100vw;
      box-sizing: border-box;
      padding: 8px;
      gap: 6px;
    }
    #header {
      font-size: 13px;
      opacity: 0.85;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    #chart-wrapper {
      flex: 1;
      position: relative;
      min-height: 0;
    }
    canvas {
      width: 100% !important;
      height: 100% !important;
      background: #181820;
      border-radius: 6px;
    }
    #audio-wrapper {
      display: flex;
      align-items: center;
      gap: 8px;
      font-size: 12px;
    }
    audio {
      width: 100%;
    }
    .legend-swatch {
      display: inline-block;
      width: 10px;
      height: 10px;
      border-radius: 2px;
      margin-right: 4px;
    }
    #upload-form {
      margin-bottom: 6px;
      font-size: 13px;
    }
    #upload-form input[type=file] {
      color: #eee;
    }
  </style>
</head>
<body>
  <div id="app">
    <form id="upload-form" method="POST" enctype="multipart/form-data">
      <span>Upload a WAV file:</span>
      <input type="file" name="audio" accept=".wav" required>
      <button type="submit">Analyze</button>
      {% if filename %}
        <span style="margin-left:8px;opacity:0.7;">Current: {{ filename }}</span>
      {% endif %}
    </form>

    {% if not filename %}
      <div style="font-size:14px;opacity:0.8;">
        Upload a .wav file above to see the Melodyne-style view.
      </div>
    {% else %}
    <div id="header">
      <div>Melodyne-style Pitch View – Rectangles = Target Notes, Line = Your Pitch</div>
      <div>
        <span class="legend-swatch" style="background:#00b400;"></span>in tune
        <span class="legend-swatch" style="background:#dcb400; margin-left:8px;"></span>slightly off
        <span class="legend-swatch" style="background:#dc0000; margin-left:8px;"></span>off
      </div>
    </div>
    <div id="chart-wrapper">
      <canvas id="pitchChart"></canvas>
    </div>
    <div id="audio-wrapper">
      <span>Audio:</span>
      <audio id="audio" controls src="{{ audio_url }}"></audio>
    </div>

    <script>
      const times = {{ times | tojson }};
      const rawF0s = {{ f0s | tojson }};
      const segments = {{ segments | tojson }};
      const pitches = rawF0s;  // already null or number

      const lineData = [];
      for (let i = 0; i < times.length; i++) {
        if (pitches[i] !== null) {
          lineData.push({ x: times[i], y: pitches[i] });
        }
      }

      const annotations = {};
      segments.forEach((seg, idx) => {
        if (seg.yMin && seg.yMax) {
          annotations["note_" + idx] = {
            type: "box",
            xMin: seg.start,
            xMax: seg.end,
            yMin: seg.yMin,
            yMax: seg.yMax,
            backgroundColor: seg.bgColor,
            borderColor: seg.borderColor,
            borderWidth: 1,
            label: {
              enabled: true,
              content: seg.note_name || "",
              position: "center",
              color: "#ddd",
              font: { size: 10 }
            }
          };
        }
      });

      const ctx = document.getElementById("pitchChart").getContext("2d");
      const chart = new Chart(ctx, {
        type: "line",
        data: {
          datasets: [{
            label: "Your Pitch",
            data: lineData,
            stepped: true,
            borderWidth: 2,
            borderColor: "#38bdf8",
            pointRadius: 0,
            pointHitRadius: 2
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: { display: false },
            annotation: { annotations: annotations },
            tooltip: {
              callbacks: {
                label: function(context) {
                  const t = context.parsed.x.toFixed(2);
                  const hz = context.parsed.y.toFixed(1);
                  return "t=" + t + "s, " + hz + " Hz";
                }
              }
            }
          },
          scales: {
            x: {
              type: "linear",
              title: { display: true, text: "Time (s)" },
              ticks: { autoSkip: true, maxTicksLimit: 10 }
            },
            y: {
              title: { display: true, text: "Pitch (Hz)" },
              ticks: { maxTicksLimit: 10 }
            }
          },
          elements: { line: { tension: 0 } }
        }
      });

      const audio = document.getElementById("audio");
      const windowSize = 3.0;
      const maxTime = times.length ? times[times.length - 1] : 0;

      audio.addEventListener("timeupdate", () => {
        const t = audio.currentTime;
        let min = t - windowSize / 2;
        let max = t + windowSize / 2;
        if (min < 0) {
          min = 0;
          max = windowSize;
        }
        if (max > maxTime) {
          max = maxTime;
          min = maxTime - windowSize;
          if (min < 0) min = 0;
        }
        chart.options.scales.x.min = min;
        chart.options.scales.x.max = max;
        chart.update("none");
      });

      if (maxTime > 0) {
        chart.options.scales.x.min = 0;
        chart.options.scales.x.max = Math.min(windowSize, maxTime);
        chart.update();
      }
    </script>
    {% endif %}
  </div>
</body>
</html>
"""


@app.route("/", methods=["GET", "POST"])
def index():
    if request.method == "POST":
        file = request.files.get("audio")
        if not file or file.filename == "":
            return redirect(url_for("index"))

        ext = os.path.splitext(file.filename)[1].lower()
        if ext != ".wav":
            return "Please upload a .wav file", 400

        fname = f"{uuid.uuid4().hex}.wav"
        fpath = os.path.join(UPLOAD_FOLDER, fname)
        file.save(fpath)

        times, f0s, segments, duration = analyze_wav(fpath)
        audio_url = url_for("uploaded_file", filename=fname)

        return render_template_string(
            TEMPLATE,
            filename=file.filename,
            audio_url=audio_url,
            times=times,
            f0s=f0s,
            segments=segments,
        )

    # GET – just show upload form
    return render_template_string(TEMPLATE, filename=None,
                                  audio_url=None, times=[], f0s=[], segments=[])


if __name__ == "__main__":
    app.run(debug=True)
