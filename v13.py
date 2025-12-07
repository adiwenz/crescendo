import argparse
import numpy as np
import sounddevice as sd
import librosa
import matplotlib.pyplot as plt
import mplcursors


# Display range
MIDI_MIN_DISPLAY = librosa.note_to_midi("C3")  # 48
MIDI_MAX_DISPLAY = librosa.note_to_midi("C6")  # 84


# ---------- Recording ----------

def record_audio(duration, sr):
    print(f"🎙 Recording for {duration} seconds... Sing now!")
    audio = sd.rec(int(duration * sr), samplerate=sr, channels=1, dtype="float32")
    sd.wait()
    print("✅ Recording done.\n")
    return audio.flatten()


# ---------- Pitch detection & basic cleaning ----------

def analyze_pitch(audio, sr, fmin=80.0, fmax=1000.0):
    """
    YIN pitch detection + basic cleaning:
      • RMS energy threshold to remove silence
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

    # --- (OUTLIER DROP #1) Silence removal via RMS energy ---
    rms = librosa.feature.rms(
        y=audio, frame_length=frame_length, hop_length=hop_length
    )[0]

    if np.max(rms) > 0:
        rms_norm = rms / np.max(rms)
    else:
        rms_norm = rms

    energy_threshold = 0.10
    voiced_mask = rms_norm > energy_threshold
    f0[~voiced_mask] = np.nan  # drop low-energy frames

    # --- (OUTLIER DROP #2) Non-positive values ---
    f0[f0 <= 0] = np.nan       # drop invalid Hz

    # --- (OUTLIER DROP #3) Neighbor filter to remove isolated "blips" ---
    voiced = ~np.isnan(f0)
    window_radius = 3
    min_voiced_in_window = 3

    for i in range(len(f0)):
        if not voiced[i]:
            continue
        start = max(0, i - window_radius)
        end = min(len(f0), i + window_radius + 1)
        if np.sum(voiced[start:end]) < min_voiced_in_window:
            f0[i] = np.nan  # isolated blip → drop

    print("✅ Pitch detection done.\n")
    return times, f0


# ---------- MIDI-domain outlier cleaning ----------

def remove_outlier_frames(midi_float, max_semitone_jump=6, window=5):
    """
    (OUTLIER DROP #4)
    Remove frames whose MIDI value is far from the local median.
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
        if len(neighbors) < 3:
            continue

        median = np.median(neighbors)
        if abs(midi[i] - median) > max_semitone_jump:
            midi[i] = np.nan  # crazy spike → drop

    return midi


# ---------- NEW: combine short MIDI note blips / gaps ----------

def smooth_nearest_notes(midi_nearest, max_flip_len=3, max_nan_gap=2):
    """
    Clean up tiny 'blips' in the nearest-note track.

    - If a short NaN gap (<= max_nan_gap) sits between the same note,
      fill it with that note.
    - If a short different-note segment (<= max_flip_len) sits between
      two runs of the same note, replace it with that note.

    This makes held notes look like ONE note even if the detector
    briefly flips for a frame or two.
    """
    midi = midi_nearest.copy()
    n = len(midi)

    # --- 1) fix short NaN gaps between identical notes ---
    i = 0
    while i < n:
        if not np.isnan(midi[i]):
            i += 1
            continue
        start = i
        j = i + 1
        while j < n and np.isnan(midi[j]):
            j += 1
        gap_len = j - start

        prev_note = midi[start - 1] if start > 0 and not np.isnan(midi[start - 1]) else None
        next_note = midi[j] if j < n and not np.isnan(midi[j]) else None

        if (
            gap_len <= max_nan_gap
            and prev_note is not None
            and next_note is not None
            and prev_note == next_note
        ):
            midi[start:j] = prev_note  # fill tiny hole

        i = j

    # --- 2) fix short different-note flips between identical notes ---
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

        # middle "flip" segment (different note)
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
            and next_end > next_start  # we actually come back to base_note
        ):
            midi[mid_start:mid_end] = base_note  # heal the flip

        # advance
        if next_end > end1:
            i = next_end
        else:
            i = end1

    return midi


# ---------- Hz → MIDI, nearest notes, cents ----------

def hz_to_note_and_cents(f0_hz):
    """
    Hz → MIDI → nearest MIDI note, note names, and cents offset (per frame).

    Steps:
      • convert Hz → MIDI
      • remove crazy MIDI spikes
      • round to nearest MIDI
      • smooth short flips / gaps in nearest notes
    """
    midi_raw = librosa.hz_to_midi(f0_hz)
    midi_clean = remove_outlier_frames(midi_raw)

    # initial nearest-note estimate
    midi_nearest_initial = np.round(midi_clean).astype(float)

    # EXTRA PASS: combine tiny blips / gaps into one note
    midi_nearest = smooth_nearest_notes(
        midi_nearest_initial,
        max_flip_len=3,
        max_nan_gap=2,
    )

    # cents relative to the *smoothed* nearest note
    cents_off = 100.0 * (midi_clean - midi_nearest)

    # Note names
    note_names = []
    for m in midi_nearest:
        if np.isnan(m):
            note_names.append("Rest")
        else:
            note_names.append(librosa.midi_to_note(int(m), octave=True))

    return midi_clean, midi_nearest, note_names, cents_off


# ---------- Collapse cents to per-note averages ----------

def average_cents_per_note(midi_nearest, cents_off):
    """
    Collapse frame-level cents into note-level averages using the
    (already smoothed) nearest-note track.
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

        seg_slice = slice(start, j)
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


# ---------- Plotting ----------

def plot_results(times, midi_float, midi_nearest, cents_note_avg, note_names):
    """
    Melodyne-ish plot:

      • y-axis limited to C3–C6
      • nearest note = orange horizontal segments (one per held note)
      • sung pitch = blue line, broken between notes
      • hover shows time, note, and NOTE-AVERAGED cents offset
    """
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

    # ----- Nearest-note segments (orange) -----
    nearest_line = np.full_like(midi_nearest_v, np.nan, dtype=float)
    n = len(midi_nearest_v)
    min_note_frames = 4  # must last at least this long to count as a note

    i = 0
    while i < n:
        if np.isnan(midi_nearest_v[i]) or np.isnan(midi_v[i]):
            i += 1
            continue

        note = midi_nearest_v[i]
        start = i
        j = i + 1
        while (
            j < n
            and not np.isnan(midi_nearest_v[j])
            and not np.isnan(midi_v[j])
            and midi_nearest_v[j] == note
        ):
            j += 1

        seg_len = j - start
        if seg_len >= min_note_frames:
            nearest_line[start:j] = note
            # break visually at boundaries so segments don't connect
            nearest_line[start] = np.nan
            nearest_line[j - 1] = np.nan

        i = j

    ax.plot(
        times_v,
        nearest_line,
        "-",
        linewidth=2.0,
        color="orange",
        label="Nearest note",
    )

    # ----- Sung pitch line (blue), broken between notes -----
    midi_line = midi_v.copy()
    for i in range(1, len(midi_line)):
        if (
            np.isnan(midi_nearest_v[i])
            or np.isnan(midi_nearest_v[i - 1])
            or midi_nearest_v[i] != midi_nearest_v[i - 1]
        ):
            midi_line[i] = np.nan
            midi_line[i - 1] = np.nan

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

    # Hover: per-note-averaged cents
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


# ---------- Main ----------

def main():
    parser = argparse.ArgumentParser(
        description="Track how on-pitch your singing is and graph it."
    )
    parser.add_argument("--duration", type=float, default=15.0)
    parser.add_argument("--sr", type=int, default=44100)
    parser.add_argument("--fmin", type=float, default=80.0)
    parser.add_argument("--fmax", type=float, default=1000.0)
    args = parser.parse_args()

    audio = record_audio(duration=args.duration, sr=args.sr)
    times, f0_hz = analyze_pitch(audio, sr=args.sr, fmin=args.fmin, fmax=args.fmax)

    midi_float, midi_nearest, note_names, cents_raw = hz_to_note_and_cents(f0_hz)
    cents_note_avg_per_frame, cents_per_note = average_cents_per_note(
        midi_nearest, cents_raw
    )

    print("Example frames (hover uses NOTE-averaged cents):")
    step = max(1, len(times) // 10)
    for t, hz, name, cents in list(
        zip(times, f0_hz, note_names, cents_note_avg_per_frame)
    )[::step]:
        if np.isnan(hz):
            continue
        print(f"  t={t:5.2f}s  {hz:7.1f} Hz  → {name:4s}  ({cents:+5.1f} cents avg)")
    print()

    summary_stats(cents_per_note)
    plot_results(times, midi_float, midi_nearest, cents_note_avg_per_frame, note_names)


if __name__ == "__main__":
    main()
