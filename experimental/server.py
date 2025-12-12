import os
import json
import numpy as np
import soundfile as sf
from flask import Flask, request, send_from_directory, render_template_string, url_for

# -------------------
# Config
# -------------------
UPLOAD_FOLDER = "uploads"
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

app = Flask(__name__)
app.config["UPLOAD_FOLDER"] = UPLOAD_FOLDER

# -------------------
# Pitch / note logic
# -------------------

NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']


def autocorr_pitch(frame, sr, fmin=80, fmax=1000):
    """Simple autocorrelation-based pitch detection."""
    corr = np.correlate(frame, frame, mode="full")[len(frame) - 1 :]
    min_lag = int(sr / fmax)
    max_lag = int(sr / fmin)

    if max_lag >= len(corr):
        return np.nan

    segment = corr[min_lag:max_lag]
    lag = np.argmax(segment) + min_lag

    if lag <= 0:
        return np.nan

    f0 = sr / lag
    if f0 < fmin or f0 > fmax:
        return np.nan

    return float(f0)


def hz_to_midi_note_info(hz):
    """Map Hz → (midi, nearest_midi, cents_error, note_name)."""
    if hz is None or hz <= 0:
        return None, None, None, None

    midi = 69 + 12 * np.log2(hz / 440.0)
    nearest = int(round(midi))
    cents = float((midi - nearest) * 100.0)
    note_name = NOTE_NAMES[nearest % 12] + str(int(nearest // 12 - 1))
    return float(midi), nearest, cents, note_name


def midi_to_hz(m):
    return float(440.0 * (2.0 ** ((m - 69) / 12.0)))


def analyze_audio(path):
    """
    Load audio, run pitch detection, build:
    - times
    - f0s
    - segments (for note rectangles)
    using the same logic as our earlier HTML.
    """
    y, sr = sf.read(path)
    if y.ndim > 1:
        y = y.mean(axis=1)
    y = y.astype(np.float32)

    win = 2048
    hop = 256

    times = []
    f0s = []

    # Frame loop
    for i in range(0, len(y) - win, hop):
        frame = y[i : i + win] * np.hamming(win)
        f0 = autocorr_pitch(frame, sr)
        if np.isnan(f0):
            f0 = None
        times.append(float(i / sr))
        f0s.append(float(f0) if f0 is not None else None)

    # Map to MIDI / cents / note names
    midis = []
    nearest_midis = []
    cents_list = []
    note_names = []

    for f in f0s:
        m, n, c, name = hz_to_midi_note_info(f)
        midis.append(m)
        nearest_midis.append(n)
        cents_list.append(c)
        note_names.append(name)

    # Build note segments: contiguous frames with same nearest MIDI
    segments = []
    current_note = None
    start_time = None
    cents_accum = []

    for t, n, c in zip(times, nearest_midis, cents_list):
        if n is None:
            if current_note is not None and cents_accum:
                segments.append(
                    {
                        "nearest_midi": current_note,
                        "start": float(start_time),
                        "end": float(t),
                        "mean_cents": float(np.nanmean(cents_accum)),
                    }
                )
            current_note = None
            start_time = None
            cents_accum = []
            continue

        if n != current_note:
            if current_note is not None and cents_accum:
                segments.append(
                    {
                        "nearest_midi": current_note,
                        "start": float(start_time),
                        "end": float(t),
                        "mean_cents": float(np.nanmean(cents_accum)),
                    }
                )
            current_note = n
            start_time = t
            cents_accum = []
        cents_accum.append(c)

    # Close last segment
    if current_note is not None and cents_accum:
        segments.append(
            {
                "nearest_midi": current_note,
                "start": float(start_time),
                "end": float(times[-1]),
                "mean_cents": float(np.nanmean(cents_accum)),
            }
        )

    # Add rectangle bounds + color based on cents error
    for seg in segments:
        m = seg["nearest_midi"]
        if m is None:
            seg["yMin"] = None
            seg["yMax"] = None
            continue
        low = midi_to_hz(m - 0.5)
        high = midi_to_hz(m + 0.5)
        seg["yMin"] = low
        seg["yMax"] = high
        seg["note_name"] = NOTE_NAMES[m % 12] + str(int(m // 12 - 1))

        err = abs(seg["mean_cents"]) if seg["mean_cents"] is not None else 999
        if err <= 20:
            color = "rgba(0, 180, 0, 0.35)"  # green
            border = "rgba(0, 220, 0, 0.8)"
        elif err <= 40:
            color = "rgba(220, 180, 0, 0.35)"  # yellow
            border = "rgba(255, 210, 0, 0.9)"
        else:
            color = "rgba(220, 0, 0, 0.35)"  # red
            border = "rgba(255, 60, 60, 0.95)"

        seg["bgColor"] = color
        seg["borderColor"] = border

    return times, f0s, segments


# -------------------
# HTML template builder
# -------------------

def build_html(audio_url, times, f0s, segments):
    """
    Build the Melodyne-style HTML page as a single string.
    Includes:
    - Chart.js + annotation plugin
    - Rectangles for notes
    - Stepped line for pitch
    - White playhead that scrolls with audio.
    """
    js_times = json.dumps(times)
    js_f0s = json.dumps(f0s)
    js_segments = json.dumps(segments)

    template = f"""
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Melodyne-Style Pitch Graph</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/chartjs-plugin-annotation@3.0.1/dist/chartjs-plugin-annotation.min.js"></script>
  <style>
    html, body {{
      margin: 0;
      padding: 0;
      height: 100%;
      width: 100%;
      background: #0c0c0f;
      color: #eee;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      overflow: hidden;
    }}
    #app {{
      display: flex;
      flex-direction: column;
      height: 100vh;
      width: 100vw;
      box-sizing: border-box;
      padding: 8px;
      gap: 6px;
    }}
    #header {{
      font-size: 13px;
      opacity: 0.85;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }}
    #chart-wrapper {{
      flex: 1;
      position: relative;
      min-height: 0;
    }}
    canvas {{
      width: 100% !important;
      height: 100% !important;
      background: #181820;
      border-radius: 6px;
    }}
    #audio-wrapper {{
      display: flex;
      align-items: center;
      gap: 8px;
      font-size: 12px;
    }}
    audio {{
      width: 100%;
    }}
    .legend-swatch {{
      display: inline-block;
      width: 10px;
      height: 10px;
      border-radius: 2px;
      margin-right: 4px;
    }}
  </style>
</head>
<body>
  <div id="app">
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
      <audio id="audio" controls src="{audio_url}"></audio>
    </div>
  </div>

  <script>
    const times = {js_times};
    const pitches = {js_f0s};
    const segments = {js_segments};

    // Build line data
    const lineData = [];
    for (let i = 0; i < times.length; i++) {{
      if (pitches[i] !== null) {{
        lineData.push({{ x: times[i], y: pitches[i] }});
      }}
    }}

    // Build annotation boxes for each note segment
    const annotations = {{}};
    segments.forEach((seg, idx) => {{
      if (seg.yMin && seg.yMax) {{
        annotations['note_' + idx] = {{
          type: 'box',
          xMin: seg.start,
          xMax: seg.end,
          yMin: seg.yMin,
          yMax: seg.yMax,
          backgroundColor: seg.bgColor,
          borderColor: seg.borderColor,
          borderWidth: 1,
          label: {{
            enabled: true,
            content: seg.note_name || '',
            position: 'center',
            color: '#ddd',
            font: {{
              size: 10
            }}
          }}
        }};
      }}
    }});

    // White playhead line
    annotations['playhead'] = {{
      type: 'line',
      xMin: 0,
      xMax: 0,
      borderColor: 'rgba(255,255,255,0.95)',
      borderWidth: 2,
      borderDash: [4, 2],
      label: {{
        enabled: false
      }}
    }};

    const ctx = document.getElementById('pitchChart').getContext('2d');

    const chart = new Chart(ctx, {{
      type: 'line',
      data: {{
        datasets: [{{
          label: 'Your Pitch',
          data: lineData,
          stepped: true,
          borderWidth: 2,
          pointRadius: 0,
          pointHitRadius: 2
        }}]
      }},
      options: {{
        responsive: true,
        maintainAspectRatio: false,
        plugins: {{
          legend: {{ display: false }},
          annotation: {{
            annotations: annotations
          }},
          tooltip: {{
            callbacks: {{
              label: function(context) {{
                const t = context.parsed.x.toFixed(2);
                const hz = context.parsed.y.toFixed(1);
                return 't=' + t + 's, ' + hz + ' Hz';
              }}
            }}
          }}
        }},
        scales: {{
          x: {{
            type: 'linear',
            title: {{
              display: true,
              text: 'Time (s)'
            }},
            ticks: {{
              autoSkip: true,
              maxTicksLimit: 10
            }}
          }},
          y: {{
            title: {{
              display: true,
              text: 'Pitch (Hz)'
            }},
            ticks: {{
              maxTicksLimit: 10
            }}
          }}
        }},
        elements: {{
          line: {{
            tension: 0
          }}
        }}
      }}
    }});

    // Auto-scroll & playhead sync
    const audio = document.getElementById('audio');
    const windowSize = 3.0;  // seconds visible
    const maxTime = times.length ? times[times.length - 1] : 0;

    audio.addEventListener('timeupdate', () => {{
      const t = audio.currentTime;
      let min = t - windowSize / 2;
      let max = t + windowSize / 2;

      if (min < 0) {{
        min = 0;
        max = windowSize;
      }}
      if (max > maxTime) {{
        max = maxTime;
        min = maxTime - windowSize;
        if (min < 0) min = 0;
      }}

      chart.options.scales.x.min = min;
      chart.options.scales.x.max = max;

      // Move playhead
      chart.options.plugins.annotation.annotations['playhead'].xMin = t;
      chart.options.plugins.annotation.annotations['playhead'].xMax = t;

      chart.update('none');
    }});

    if (maxTime > 0) {{
      chart.options.scales.x.min = 0;
      chart.options.scales.x.max = Math.min(windowSize, maxTime);
      chart.update();
    }}
  </script>
</body>
</html>
"""
    return template


# -------------------
# Flask routes
# -------------------

@app.route("/", methods=["GET"])
def index():
    # Simple upload form
    return """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Upload Audio for Melodyne-Style Graph</title>
    </head>
    <body style="font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;">
      <h1>Upload Audio</h1>
      <form action="/upload" method="post" enctype="multipart/form-data">
        <input type="file" name="audio" accept="audio/*" required>
        <button type="submit">Generate Pitch Graph</button>
      </form>
    </body>
    </html>
    """


@app.route("/upload", methods=["POST"])
def upload():
    file = request.files.get("audio")
    if not file:
        return "No file uploaded", 400

    filename = file.filename
    save_path = os.path.join(app.config["UPLOAD_FOLDER"], filename)
    file.save(save_path)

    # Analyze the audio
    times, f0s, segments = analyze_audio(save_path)

    # Build URL for the audio route
    audio_url = url_for("serve_audio", filename=filename)

    # Build HTML and return
    html = build_html(audio_url, times, f0s, segments)
    return render_template_string(html)


@app.route("/audio/<path:filename>")
def serve_audio(filename):
    return send_from_directory(app.config["UPLOAD_FOLDER"], filename)


if __name__ == "__main__":
    app.run(debug=True)
