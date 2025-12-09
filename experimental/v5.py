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
    Smooth very short note segments (1–2 frames) between longer ones by
    replacing them with the average of neighboring segments.
    Operates on the continuous MIDI track (before snapping to semitones).
    """
    midi = midi_float.copy()
    n = len(midi)
    midi_near = np.round(midi)

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

    for idx in range(1, len(segments) - 1):
        s_start, s_end, _ = segments[idx]
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


def remove_outlier_frames(midi_float, max_semitone_jump=4, window=4):
    """
    Remove frames whose MIDI value is 'vastly different' from their local
    neighborhood. Those are treated as outliers and set to NaN.
    """
    midi = midi_float.copy()
    n = len(midi)

    for i in range(n):
        if np.isnan(midi[i]):
            continue

        start = max(0, i - window)
        end = min(n, i + window + 1)
        neighbors = midi[start:end]
        neighbors = neighbors[~np.isnan(neighbors)]

        # need at least a few neighbors to judge
        if len(neighbors) < 3:
            continue

        median = np.median(neighbors)
        if abs(midi[i] - median) > max_semitone_jump:
            midi[i] = np.nan

    return midi


# ---------- NEW: smooth tiny nearest-note flips between same note ----------

def smooth_nearest_note_flips(midi_nearest, max_flip_len=20):
    """
    Merge very short different-note 'flips' between two runs of the same note.

    Example: A A A  B  A A A, where B lasts <= max_flip_len frames,
    becomes:  A A A  A  A A A.

    This removes little orange outliers between what should be a single note.
    """
    midi = midi_nearest.copy()
    n = len(midi)
    i = 0

    while i < n:
        if np.isnan(midi[i]):
            i += 1
            continue

        base_note = midi[i]

        # first segment of base_note
        start1 = i
        j = i + 1
        while j < n and not np.isnan(midi[j]) and midi[j] == base_note:
            j += 1
        end1 = j

        # middle flip segment (different note)
        mid_start = end1
        mid_end = mid_start
        while mid_end < n and not np.isnan(midi[mid_end]) and midi[mid_end] != base_note:
            mid_end += 1
        flip_len = mid_end - mid_start

        # following base_note segment
        next_start = mid_end
        next_end = next_start
        while (
            next_end < n
            and not np.isnan(midi[next_end])
            and midi[next_end] == base_note
        ):
            next_end += 1

        if (
            flip_len > 0
            and flip_len <= max_flip_len
            and next_end > next_start  # we actually return to base_note
        ):
            # Replace the tiny middle flip with the base note
            midi[mid_start:mid_end] = base_note

        # advance
        if next_end > end1:
            i = next_end
        else:
            i = end1

    return midi


def hz_to_note_and_cents(f0_hz):
    """
    Hz → MIDI → nearest MIDI note, note names, and raw cents offset (per frame).

    Processing steps:
      • convert Hz → MIDI
      • smooth very short jumps (continuous MIDI)
      • remove outliers on continuous MIDI
      • round to nearest MIDI note
      • remove outliers on snapped MIDI notes
      • smooth tiny nearest-note flips between same note
    """
    # Raw continuous MIDI
    midi_raw = librosa.hz_to_midi(f0_hz)

    # Smooth tiny jumps and drop outliers (continuous MIDI)
    midi_smooth = smooth_short_jumps(midi_raw, max_len=2)
    midi_clean = remove_outlier_frames(
        midi_smooth, max_semitone_jump=4, window=4
    )

    # Snap to nearest semitone
    midi_nearest = np.round(midi_clean).astype(float)

    # ALSO remove outliers on the snapped notes themselves
    midi_nearest_clean = remove_outlier_frames(
        midi_nearest, max_semitone_jump=4, window=4
    )

    # Any frame that was outlier in snapped notes → drop from continuous too
    bad = np.isnan(midi_nearest_clean)
    midi_clean[bad] = np.nan
    midi_nearest = midi_nearest_clean

    # Merge very short wrong-note flips between two runs of the same note
    midi_nearest = smooth_nearest_note_flips(midi_nearest, max_flip_len=40)

    # Cents offset from nearest note
    cents_off = 100.0 * (midi_clean - midi_nearest)

    # Note names (or "Rest" for NaNs)
    note_names = []
    for m in midi_nearest:
        if np.isnan(m):
            note_names.append("Rest")
        else:
            note_names.append(librosa.midi_to_note(int(m), octave=True))

    return midi_clean, midi_nearest, note_names, cents_off


def average_cents_per_note(midi_nearest, cents_off):
    """
    Collapse frame-level cents into note-level averages.
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
    """Stats over note-level average cents."""
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


# ---------- Mask short nearest-note segments for plotting ----------

def mask_short_nearest_segments(midi_nearest, cents, min_len=10, max_cents=100.0):
    """
    For visualization:

      • Keep only nearest-note segments that last at least `min_len` frames
        AND whose average |cents| <= max_cents.
      • Treat everything else as 'silence' (set to NaN) so it does NOT
        get plotted.

    This removes:
      • tiny orange blips (short segments)
      • 'staircase' notes in slides where the pitch is far from the
        snapped note (large cents error).
    """
    midi = midi_nearest.copy()
    n = len(midi)
    i = 0

    while i < n:
        if np.isnan(midi[i]):
            i += 1
            continue

        note = midi[i]
        start = i
        j = i + 1
        while (
            j < n
            and not np.isnan(midi[j])
            and midi[j] == note
        ):
            j += 1

        seg_len = j - start
        seg_cents = cents[start:j]
        valid_cents = seg_cents[~np.isnan(seg_cents)]
        avg_abs_cents = np.mean(np.abs(valid_cents)) if valid_cents.size > 0 else np.inf

        # Hide if too short OR too out-of-tune (likely part of a slide)
        if seg_len < min_len or avg_abs_cents > max_cents:
            midi[start:j] = np.nan

        i = j

    return midi


def median_smooth_midi_for_plot(midi_nearest, window=9):
    """
    Simple median filter over the nearest-note track, used ONLY for
    plotting. This collapses fast flips (e.g. A–B–A–B) into a single
    stable note for visualization.
    """
    midi = midi_nearest.copy()
    n = len(midi)
    out = np.full_like(midi, np.nan, dtype=float)
    half = window // 2

    for i in range(n):
        start = max(0, i - half)
        end = min(n, i + half + 1)
        vals = midi[start:end]
        vals = vals[~np.isnan(vals)]
        if len(vals) == 0:
            continue
        out[i] = np.median(vals)

    return out


def plot_results(times, midi_float, midi_nearest, cents_note_avg, note_names):
    """
    Interactive Melodyne-style plot:

      • y-axis limited to C3–C6
      • nearest note = orange dots (short blips hidden)
      • sung pitch = blue line, broken when nearest note changes
      • hover shows time, note, and NOTE-AVERAGED cents offset
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

    # Smooth nearest-note track for plotting, then hide tiny / slide-ish bits
    midi_nearest_smooth = median_smooth_midi_for_plot(midi_nearest_v, window=5)
    midi_nearest_plot = mask_short_nearest_segments(
        midi_nearest_smooth,
        cents_v,
        min_len=10,
        max_cents=120.0,
    )

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
        midi_nearest_plot,
        ".",
        markersize=4,
        alpha=0.7,
        color="orange",
        label="Nearest note",
    )

    # Break the sung pitch only on BIG note jumps (>= 3 semitones) or NaNs
    midi_line = midi_v.copy()
    for i in range(1, len(midi_line)):
        if (
            np.isnan(midi_v[i]) or np.isnan(midi_v[i - 1])
            or abs(midi_nearest_v[i] - midi_nearest_v[i - 1]) >= 3   # <= KEY LINE
        ):
            midi_line[i] = np.nan
            midi_line[i - 1] = np.nan

    # Plot sung pitch line (blue)
    ax.plot(
        times_v,
        midi_line,
        "-",
        linewidth=1.5,
        label="Sung pitch (MIDI)",
    )

    # Invisible scatter just for hover picking
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
        default=5.0,
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

    # 3) MIDI + cents (with smoothing & outlier removal)
    midi_float, midi_nearest, note_names, cents_raw = hz_to_note_and_cents(f0_hz)

    # 4) Convert to NOTE-LEVEL averages
    cents_note_avg_per_frame, cents_per_note = average_cents_per_note(
        midi_nearest, cents_raw
    )

    # 5) Example frames
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
