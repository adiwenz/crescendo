import argparse
import numpy as np
import sounddevice as sd
import librosa
import matplotlib.pyplot as plt
import mplcursors


# Fixed display range
MIDI_MIN_DISPLAY = librosa.note_to_midi("C3")  # 48
MIDI_MAX_DISPLAY = librosa.note_to_midi("C6")  # 84


def record_audio(duration, sr):
    print(f"🎙 Recording for {duration} seconds... Sing now!")
    audio = sd.rec(int(duration * sr), samplerate=sr, channels=1, dtype="float32")
    sd.wait()
    print("✅ Recording done.\n")
    return audio.flatten()


def analyze_pitch(audio, sr, fmin=80.0, fmax=1000.0):
    """
    YIN pitch detection + basic cleaning:
      • RMS energy threshold
      • neighbor filter to remove isolated blips
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

    # --- Silence removal via RMS energy ---
    rms = librosa.feature.rms(
        y=audio, frame_length=frame_length, hop_length=hop_length
    )[0]

    if np.max(rms) > 0:
        rms_norm = rms / np.max(rms)
    else:
        rms_norm = rms

    energy_threshold = 0.10  # tweak if needed
    voiced_mask = rms_norm > energy_threshold
    f0[~voiced_mask] = np.nan

    # Replace non-positive values with NaN
    f0[f0 <= 0] = np.nan

    # --- Neighbor filter to remove isolated "blips" ---
    voiced = ~np.isnan(f0)
    window_radius = 3
    min_voiced_in_window = 3

    for i in range(len(f0)):
        if not voiced[i]:
            continue
        start = max(0, i - window_radius)
        end = min(len(f0), i + window_radius + 1)
        if np.sum(voiced[start:end]) < min_voiced_in_window:
            f0[i] = np.nan

    print("✅ Pitch detection done.\n")
    return times, f0


def smooth_short_jumps(midi_float, max_len=2):
    """
    Look for very short note segments (1–2 frames) between longer segments
    and replace their MIDI values with the average of their neighboring segments.

    This turns A–B–A where len(B) <= max_len into a smoother line.
    """
    midi = midi_float.copy()
    n = len(midi)
    midi_near = np.round(midi)

    # Build segments of contiguous equal midi_near (ignoring NaNs)
    segments = []
    i = 0
    while i < n:
        if np.isnan(midi[i]):
            i += 1
            continue
        note = midi_near[i]
        start = i
        j = i + 1
        while (
            j < n
            and not np.isnan(midi[j])
            and np.round(midi[j]) == note
        ):
            j += 1
        segments.append((start, j, note))
        i = j

    # Smooth short middle segments
    for idx in range(1, len(segments) - 1):
        s_start, s_end, s_note = segments[idx]
        seg_len = s_end - s_start
        if seg_len > max_len:
            continue

        prev_start, prev_end, _ = segments[idx - 1]
        next_start, next_end, _ = segments[idx + 1]

        prev_mean = np.nanmean(midi[prev_start:prev_end])
        next_mean = np.nanmean(midi[next_start:next_end])
        replacement = (prev_mean + next_mean) / 2.0

        midi[s_start:s_end] = replacement

    return midi


def hz_to_note_and_cents(f0_hz):
    """
    Hz → MIDI → nearest MIDI note, note names, and raw cents offset (per frame).
    Includes extra smoothing step on MIDI to remove short jumps.
    """
    midi_raw = librosa.hz_to_midi(f0_hz)

    # Extra smoothing of super-short jumps
    midi_float = smooth_short_jumps(midi_raw, max_len=2)

    midi_nearest = np.round(midi_float).astype(float)
    cents_off = 100.0 * (midi_float - midi_nearest)

    note_names = []
    for m in midi_nearest:
        if np.isnan(m):
            note_names.append("Rest")
        else:
            note_names.append(librosa.midi_to_note(int(m), octave=True))

    return midi_float, midi_nearest, note_names, cents_off


def average_cents_per_note(midi_nearest, cents_off):
    """
    Collapse frame-level cents into note-level averages.

    A "note" = contiguous region where midi_nearest is the same (and not NaN).
    Returns:
        cents_avg_per_frame: array same length as input, but each frame
                             within a note segment gets that segment's mean cents.
        cents_per_note: 1D array of unique segment means, one per sung note.
    """
    n = len(midi_nearest)
    cents_avg = np.full_like(cents_off, np.nan, dtype=float)
    segment_means = []

    i = 0
    while i < n:
        if np.isnan(midi_nearest[i]):
            i += 1
            continue

        note = midi_nearest[i]
        start = i
        j = i + 1
        while (
            j < n
            and not np.isnan(midi_nearest[j])
            and midi_nearest[j] == note
        ):
            j += 1

        seg_slice = slice(i, j)
        seg_cents = cents_off[seg_slice]
        valid = ~np.isnan(seg_cents)

        if np.any(valid):
            mean_cents = float(np.mean(seg_cents[valid]))
            cents_avg[seg_slice] = mean_cents
            segment_means.append(mean_cents)

        i = j

    return cents_avg, np.array(segment_means, dtype=float)


def summary_stats(cents_per_note):
    """Stats over note-level average cents, not every frame."""
    valid = ~np.isnan(cents_per_note)
    if not np.any(valid):
        print("⚠️ No valid pitch detected (maybe too quiet or too noisy?).")
        return

    vals = cents_per_note[valid]
    abs_cents = np.abs(vals)

    within_25 = np.mean(abs_cents <= 25) * 100.0
    within_50 = np.mean(abs_cents <= 50) * 100.0
    avg_abs = np.mean(abs_cents)

    print("📊 Tuning summary (per sung note):")
    print(f"   • Avg absolute error: {avg_abs:.1f} cents")
    print(f"   • % of notes within ±25 cents: {within_25:.1f}%")
    print(f"   • % of notes within ±50 cents: {within_50:.1f}%\n")


def plot_results(times, midi_float, midi_nearest, cents_note_avg, note_names):
    """
    Interactive Melodyne-style plot:

      • y-axis limited to C3–C6
      • nearest note = orange dots
      • sung pitch = blue line
      • hover shows time, note name, and NOTE-AVERAGED cents offset
    """
    # Only plot frames with valid pitch in display range
    valid = (
        ~np.isnan(midi_float)
        & (midi_float >= MIDI_MIN_DISPLAY)
        & (midi_float <= MIDI_MAX_DISPLAY)
    )
    if not np.any(valid):
        print("⚠️ Nothing to plot in C3–C6 range.")
        return

    times_v = times[valid]
    midi_v = midi_float[valid]
    midi_nearest_v = midi_nearest[valid]
    cents_v = cents_note_avg[valid]
    notes_v = np.array(note_names)[valid]

    midi_ticks = list(range(MIDI_MIN_DISPLAY, MIDI_MAX_DISPLAY + 1))
    midi_labels = [librosa.midi_to_note(m, octave=True) for m in midi_ticks]

    fig, ax = plt.subplots(figsize=(12, 6))

    ax.set_title("Sung Pitch vs Nearest Note")
    ax.set_ylabel("Note")
    ax.set_xlabel("Time (s)")

    # Note lanes
    for m in midi_ticks:
        ax.axhline(m, linestyle=":", linewidth=0.5, alpha=0.3)

    # Nearest snapped notes in orange (dots)
    ax.plot(
        times_v,
        midi_nearest_v,
        ".",
        markersize=4,
        alpha=0.7,
        color="orange",
        label="Nearest note",
    )

    # Sung pitch as a line (blue)
    line, = ax.plot(
        times_v,
        midi_v,
        "-",
        linewidth=1.5,
        label="Sung pitch (MIDI)",
    )

    # Invisible scatter just for picking with mplcursors
    scatter = ax.scatter(times_v, midi_v, s=10, alpha=0.0)

    ax.set_yticks(midi_ticks)
    ax.set_yticklabels(midi_labels)
    ax.set_ylim(MIDI_MIN_DISPLAY, MIDI_MAX_DISPLAY)
    ax.legend(loc="upper right")

    # Interactive hover: NOTE-AVERAGED cents
    cursor = mplcursors.cursor(scatter, hover=True)

    @cursor.connect("add")
    def on_add(sel):
        i = sel.index
        t = times_v[i]
        note = notes_v[i]
        cents = cents_v[i]
        sel.annotation.set_text(
            f"t = {t:.2f} s\n{note}\n{cents:+.1f} cents (avg)"
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

    # 2) Detect pitch over time
    times, f0_hz = analyze_pitch(audio, sr=args.sr, fmin=args.fmin, fmax=args.fmax)

    # 3) Frame-level MIDI + cents (with short-jump smoothing inside)
    midi_float, midi_nearest, note_names, cents_raw = hz_to_note_and_cents(f0_hz)

    # 4) Convert to NOTE-LEVEL averages
    cents_note_avg_per_frame, cents_per_note = average_cents_per_note(
        midi_nearest, cents_raw
    )

    # 5) Print a few sample frames
    print("Example frames (hover uses NOTE-averaged cents):")
    step = max(1, len(times) // 10)
    for t, hz, name, cents in list(
        zip(times, f0_hz, note_names, cents_note_avg_per_frame)
    )[::step]:
        if np.isnan(hz):
            continue
        print(f"  t={t:5.2f}s  {hz:7.1f} Hz  → {name:4s}  ({cents:+5.1f} cents avg)")
    print()

    # 6) Summary over note-level averages
    summary_stats(cents_per_note)

    # 7) Plot
    plot_results(
        times,
        midi_float,
        midi_nearest,
        cents_note_avg_per_frame,
        note_names,
    )


if __name__ == "__main__":
    main()
