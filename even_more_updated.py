import argparse
import numpy as np
import sounddevice as sd
import librosa
import matplotlib.pyplot as plt
import mplcursors


def record_audio(duration, sr):
    print(f"🎙 Recording for {duration} seconds... Sing now!")
    audio = sd.rec(int(duration * sr), samplerate=sr, channels=1, dtype="float32")
    sd.wait()
    print("✅ Recording done.\n")
    return audio.flatten()


def analyze_pitch(audio, sr, fmin=80.0, fmax=1000.0):
    """
    Use librosa.yin to estimate pitch (F0) over time.
    Also removes silence / noise using:
      • RMS energy threshold
      • A simple neighbor filter to kill isolated "straggler" notes
    Returns:
        times: np.ndarray of times (s)
        f0_hz: np.ndarray of detected F0 in Hz (NaN where unvoiced / silence)
    """
    frame_length = 2048
    hop_length = 256

    print("🎼 Running pitch detection (YIN)...")
    f0 = librosa.yin(
        audio,
        fmin=fmin,
        fmax=fmax,
        sr=sr,
        frame_length=frame_length,
        hop_length=hop_length,
    )

    times = librosa.times_like(f0, sr=sr, hop_length=hop_length)
    f0 = np.array(f0, dtype=float)

    # --- Voice activity / silence removal based on energy ---
    rms = librosa.feature.rms(
        y=audio, frame_length=frame_length, hop_length=hop_length
    )[0]

    if np.max(rms) > 0:
        rms_norm = rms / np.max(rms)
    else:
        rms_norm = rms

    # Slightly stricter threshold to remove more silence-generated junk
    energy_threshold = 0.10
    voiced_mask = rms_norm > energy_threshold
    f0[~voiced_mask] = np.nan

    # Replace non-positive values with NaN
    f0[f0 <= 0] = np.nan

    # --- Neighbor filter to remove isolated "blips" ---
    # If a voiced frame doesn't have enough voiced neighbors in a small window,
    # treat it as noise and drop it.
    voiced = ~np.isnan(f0)
    window_radius = 3          # frames on each side
    min_voiced_in_window = 3   # minimum voiced frames required to keep it

    for i in range(len(f0)):
        if not voiced[i]:
            continue
        start = max(0, i - window_radius)
        end = min(len(f0), i + window_radius + 1)
        if np.sum(voiced[start:end]) < min_voiced_in_window:
            f0[i] = np.nan

    print("✅ Pitch detection done.\n")
    return times, f0


def hz_to_note_and_cents(f0_hz):
    """
    Convert Hz → MIDI note, nearest note name, and cents offset.
    Returns:
        midi_float: float MIDI values
        midi_nearest: float (nearest semitone as MIDI)
        note_names: list of strings like 'A4'
        cents_off: float cents offset from nearest note
    """
    midi_float = librosa.hz_to_midi(f0_hz)

    midi_nearest = np.round(midi_float).astype(float)
    cents_off = 100.0 * (midi_float - midi_nearest)

    note_names = []
    for m in midi_nearest:
        if np.isnan(m):
            note_names.append("Rest")
        else:
            note_names.append(librosa.midi_to_note(int(m), octave=True))

    return midi_float, midi_nearest, note_names, cents_off


def summary_stats(cents_off):
    """Compute and print some basic tuning stats."""
    valid = ~np.isnan(cents_off)
    if not np.any(valid):
        print("⚠️ No valid pitch detected (maybe too quiet or too noisy?).")
        return

    valid_cents = cents_off[valid]
    abs_cents = np.abs(valid_cents)

    within_25 = np.mean(abs_cents <= 25) * 100.0
    within_50 = np.mean(abs_cents <= 50) * 100.0
    avg_abs = np.mean(abs_cents)

    print("📊 Tuning summary (where pitch was detected):")
    print(f"   • Avg absolute error: {avg_abs:.1f} cents")
    print(f"   • % of time within ±25 cents: {within_25:.1f}%")
    print(f"   • % of time within ±50 cents: {within_50:.1f}%\n")


def plot_results(times, midi_float, midi_nearest, cents_off, note_names):
    """
    Single Melodyne-ish plot, interactive:
      • y-axis = note (MIDI, labeled as note names)
      • Nearest note shown in ORANGE
      • Hover any point to see time, note, and cents offset
    """
    valid = ~np.isnan(midi_float)
    if not np.any(valid):
        print("⚠️ Nothing to plot (no valid pitch frames).")
        return

    times_v = times[valid]
    midi_v = midi_float[valid]
    midi_nearest_v = midi_nearest[valid]
    cents_v = cents_off[valid]
    notes_v = np.array(note_names)[valid]

    # Limit Y range to lowest/ highest used note ± 1 semitone
    midi_min = int(np.floor(np.min(midi_v))) - 1
    midi_max = int(np.ceil(np.max(midi_v))) + 1
    midi_ticks = list(range(midi_min, midi_max + 1))
    midi_labels = [librosa.midi_to_note(m, octave=True) for m in midi_ticks]

    fig, ax = plt.subplots(figsize=(12, 6))

    ax.set_title("Sung Pitch vs Nearest Note")
    ax.set_ylabel("Note")
    ax.set_xlabel("Time (s)")

    # Note lanes
    for m in midi_ticks:
        ax.axhline(m, linestyle=":", linewidth=0.5, alpha=0.3)

    # Nearest snapped notes in ORANGE
    ax.plot(
        times_v,
        midi_nearest_v,
        ".",
        markersize=4,
        alpha=0.7,
        color="orange",
        label="Nearest note",
    )

    # Actual sung pitch (scatter) – default color (blue)
    scatter = ax.scatter(
        times_v,
        midi_v,
        s=10,
        label="Sung pitch (MIDI)",
    )

    ax.set_yticks(midi_ticks)
    ax.set_yticklabels(midi_labels)
    ax.set_ylim(midi_min, midi_max)
    ax.legend(loc="upper right")

    # --- Interactive hover with mplcursors ---
    cursor = mplcursors.cursor(scatter, hover=True)

    @cursor.connect("add")
    def on_add(sel):
        i = sel.index
        t = times_v[i]
        note = notes_v[i]
        cents = cents_v[i]
        sel.annotation.set_text(
            f"t = {t:.2f} s\n{note}\n{cents:+.1f} cents"
        )

    plt.tight_layout()
    plt.show()


def main():
    parser = argparse.ArgumentParser(
        description="Track how on-pitch your singing is and graph it."
    )
    parser.add_argument(
        "--duration",
        type=float,
        default=15.0,
        help="Recording duration in seconds (default: 15)",
    )
    parser.add_argument(
        "--sr",
        type=int,
        default=44100,
        help="Sample rate in Hz (default: 44100)",
    )
    parser.add_argument(
        "--fmin",
        type=float,
        default=80.0,
        help="Minimum pitch to detect in Hz (default: 80)",
    )
    parser.add_argument(
        "--fmax",
        type=float,
        default=1000.0,
        help="Maximum pitch to detect in Hz (default: 1000)",
    )

    args = parser.parse_args()

    # 1) Record from mic
    audio = record_audio(duration=args.duration, sr=args.sr)

    # 2) Detect pitch over time (with silence + straggler removal)
    times, f0_hz = analyze_pitch(audio, sr=args.sr, fmin=args.fmin, fmax=args.fmax)

    # 3) Convert to musical notes + cents error
    midi_float, midi_nearest, note_names, cents_off = hz_to_note_and_cents(f0_hz)

    # 4) Print some example frames
    print("Example frames:")
    step = max(1, len(times) // 10)
    for t, hz, name, cents in list(
        zip(times, f0_hz, note_names, cents_off)
    )[::step]:
        if np.isnan(hz):
            continue
        print(f"  t={t:5.2f}s  {hz:7.1f} Hz  → {name:4s}  ({cents:+5.1f} cents)")
    print()

    # 5) Summary stats
    summary_stats(cents_off)

    # 6) Plot interactive Melodyne-ish graph
    plot_results(times, midi_float, midi_nearest, cents_off, note_names)


if __name__ == "__main__":
    main()
