import argparse
import numpy as np
import sounddevice as sd
import librosa
import matplotlib.pyplot as plt


def record_audio(duration, sr):
    print(f"🎙 Recording for {duration} seconds... Sing now!")
    audio = sd.rec(int(duration * sr), samplerate=sr, channels=1, dtype="float32")
    sd.wait()
    print("✅ Recording done.\n")
    return audio.flatten()


def analyze_pitch(audio, sr, fmin=80.0, fmax=1000.0):
    """
    Use librosa.yin to estimate pitch (F0) over time.
    Returns:
        times: np.ndarray of times (s)
        f0_hz: np.ndarray of detected F0 in Hz (NaN where unvoiced)
    """
    # Frame & hop sizes are a tradeoff between time resolution & stability
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
    f0 = np.array(f0)
    # Replace negative / zero with NaN
    f0[f0 <= 0] = np.nan

    print("✅ Pitch detection done.\n")
    return times, f0


def hz_to_note_and_cents(f0_hz):
    """
    Convert Hz → MIDI note, nearest note name, and cents offset.
    Returns:
        midi_float: float MIDI values
        midi_nearest: int MIDI values (nearest semitone)
        note_names: list of strings like 'A4'
        cents_off: float cents offset from nearest note
    """
    # Ignore NaNs safely
    midi_float = librosa.hz_to_midi(f0_hz)
    midi_nearest = np.round(midi_float).astype(int)

    cents_off = 100.0 * (midi_float - midi_nearest)

    note_names = []
    for m in midi_nearest:
        if np.isnan(m):
            note_names.append("Rest")
        else:
            note_names.append(librosa.midi_to_note(m, octave=True))

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


def plot_results(times, midi_float, midi_nearest, cents_off):
    """Create Melodyne-ish plots: pitch vs time, plus cents error."""
    # Focus y-axis on the range actually used
    valid_midi = midi_float[~np.isnan(midi_float)]
    if len(valid_midi) == 0:
        print("⚠️ Nothing to plot (no valid pitch frames).")
        return

    midi_min = int(np.floor(valid_midi.min())) - 1
    midi_max = int(np.ceil(valid_midi.max())) + 1
    midi_ticks = list(range(midi_min, midi_max + 1))
    midi_labels = [librosa.midi_to_note(m, octave=True) for m in midi_ticks]

    fig, (ax1, ax2) = plt.subplots(
        2, 1, figsize=(12, 8), sharex=True, gridspec_kw={"height_ratios": [3, 1]}
    )

    # --- Top plot: pitch curve with note lanes ---
    ax1.set_title("Sung Pitch vs Nearest Note")
    ax1.set_ylabel("Note")

    # Horizontal “note lanes”
    for m in midi_ticks:
        ax1.axhline(m, linestyle=":", linewidth=0.5, alpha=0.3)

    # Plot sung pitch
    ax1.plot(times, midi_float, ".", markersize=4, label="Sung pitch (MIDI)")

    # Plot nearest semitone (like Melodyne snapping)
    ax1.plot(times, midi_nearest, ".", markersize=3, alpha=0.4, label="Nearest note")

    ax1.set_yticks(midi_ticks)
    ax1.set_yticklabels(midi_labels)
    ax1.legend(loc="upper right")

    # --- Bottom plot: cents error over time ---
    ax2.set_title("Cents Offset from Nearest Note")
    ax2.set_xlabel("Time (s)")
    ax2.set_ylabel("Cents")

    ax2.axhline(0, linewidth=1)
    ax2.axhline(25, linestyle="--", linewidth=0.8)
    ax2.axhline(-25, linestyle="--", linewidth=0.8)

    ax2.plot(times, cents_off, ".", markersize=4)
    ax2.set_ylim(-100, 100)

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

    # 2) Detect pitch over time
    times, f0_hz = analyze_pitch(audio, sr=args.sr, fmin=args.fmin, fmax=args.fmax)

    # 3) Convert to musical notes + cents error
    midi_float, midi_nearest, note_names, cents_off = hz_to_note_and_cents(f0_hz)

    # Optional: print a few sample lines
    print("Example frames:")
    for t, hz, name, cents in list(
        zip(times, f0_hz, note_names, cents_off)
    )[:: max(1, len(times) // 10)]:
        if np.isnan(hz):
            continue
        print(f"  t={t:5.2f}s  {hz:7.1f} Hz  → {name:4s}  ({cents:+5.1f} cents)")

    print()
    # 4) Print summary stats
    summary_stats(cents_off)

    # 5) Plot Melodyne-style graphs
    plot_results(times, midi_float, midi_nearest, cents_off)


if __name__ == "__main__":
    main()
