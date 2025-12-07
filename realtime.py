import time
import queue
from collections import deque

import numpy as np
import sounddevice as sd
import librosa
import matplotlib.pyplot as plt


SR = 44100
BLOCKSIZE = 1024          # audio frames per callback
FMIN = 80.0
FMAX = 1000.0
BUFFER_SECONDS = 4        # how much recent audio we analyze
WINDOW_SECONDS = 3       # how much history to show on the graph

# For display range
MIDI_MIN_DISPLAY = librosa.note_to_midi("C3")
MIDI_MAX_DISPLAY = librosa.note_to_midi("C5")

# Audio buffer + queue from callback → main thread
audio_buffer = deque(maxlen=int(BUFFER_SECONDS * SR))
block_queue = queue.Queue()

# Pitch history (for plotting)
times = []
midi_vals = []
midi_nearest_vals = []

start_time = None


def audio_callback(indata, frames, time_info, status):
    """Called by sounddevice in the audio thread."""
    if status:
        print(status)
    # Copy to avoid using the same memory after callback returns
    block_queue.put(indata[:, 0].copy())


def process_audio():
    """Pull blocks from queue, update audio buffer, estimate pitch."""
    # 1) Move blocks from queue into the buffer
    while not block_queue.empty():
        block = block_queue.get_nowait()
        audio_buffer.extend(block)

    # Need enough samples to run YIN
    frame_length = 2048
    hop_length = 256
    if len(audio_buffer) < frame_length:
        return None, None, None

    y = np.array(audio_buffer, dtype=np.float32)

    # 2) Run YIN over the buffered audio
    f0 = librosa.yin(
        y,
        fmin=FMIN,
        fmax=FMAX,
        sr=SR,
        frame_length=frame_length,
        hop_length=hop_length,
    )

    f0_val = float(f0[-1])  # use the most recent estimate
    if f0_val <= 0 or np.isnan(f0_val):
        return None, None, None

    midi = librosa.hz_to_midi(f0_val)
    midi_nearest = round(midi)

    return f0_val, midi, midi_nearest


def main():
    global start_time

    plt.ion()
    fig, ax = plt.subplots(figsize=(10, 5))
    line_pitch, = ax.plot([], [], "-", label="Sung pitch (MIDI)")
    scatter_nearest = ax.plot([], [], "-", color="orange", markersize=1,
                              label="Nearest note")[0]
    # scatter_nearest = ax.plot([], [], "o", color="orange", markersize=1,
    #                           label="Nearest note")[0]

    midi_ticks = list(range(MIDI_MIN_DISPLAY, MIDI_MAX_DISPLAY + 1))
    midi_labels = [librosa.midi_to_note(m, octave=True) for m in midi_ticks]

    ax.set_ylim(MIDI_MIN_DISPLAY, MIDI_MAX_DISPLAY)
    ax.set_yticks(midi_ticks)
    ax.set_yticklabels(midi_labels)
    ax.set_xlabel("Time (s)")
    ax.set_ylabel("Note")
    ax.set_title("Realtime Sung Pitch vs Nearest Note")
    ax.legend(loc="upper right")

    start_time = time.time()

    print("🎙 Starting realtime pitch display. Sing into your mic (Ctrl+C to stop).")

    with sd.InputStream(
        samplerate=SR,
        channels=1,
        blocksize=BLOCKSIZE,
        callback=audio_callback,
    ):
        try:
            while True:
                f0_val, midi, midi_nearest = process_audio()
                t_now = time.time() - start_time

                # If we don't even have an f0 estimate yet, just skip
                if f0_val is None or midi is None or np.isnan(midi):
                    print(f"{t_now:.2f}s: not enough data yet or no pitch")
                    plt.pause(0.01)
                    continue

                # Decide if this is a valid pitch or "silence"
                # Here we treat MIDI values outside the display range as silence.
                is_valid_pitch = (
                    MIDI_MIN_DISPLAY <= midi <= MIDI_MAX_DISPLAY
                )

                times.append(t_now)

                if is_valid_pitch:
                    print(f"{t_now:.2f}s: VALID pitch  f0={f0_val:.1f} Hz, midi={midi:.2f}")
                    midi_vals.append(midi)
                    midi_nearest_vals.append(midi_nearest)
                else:
                    # This is where we BREAK the line: we append NaN
                    print(
                        f"{t_now:.2f}s: SILENCE/INVALID  f0={f0_val:.1f} Hz, midi={midi:.2f} -> NaN"
                    )
                    midi_vals.append(np.nan)
                    midi_nearest_vals.append(np.nan)

                # Keep only the last WINDOW_SECONDS of data
                while times and (t_now - times[0]) > WINDOW_SECONDS:
                    times.pop(0)
                    midi_vals.pop(0)
                    midi_nearest_vals.pop(0)

                # Update plot data – this is where the line is actually drawn
                line_pitch.set_data(times, midi_vals)
                scatter_nearest.set_data(times, midi_nearest_vals)

                ax.set_xlim(max(0, t_now - WINDOW_SECONDS), t_now)

                plt.pause(0.001)  # ~1 FPS

        except KeyboardInterrupt:
            print("\n👋 Stopped.")


if __name__ == "__main__":
    main()
