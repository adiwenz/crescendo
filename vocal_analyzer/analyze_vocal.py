import argparse
import os
import numpy as np
import librosa
import pretty_midi
import soundfile as sf

# -----------------------------------
# Helper functions
# -----------------------------------

def hz_to_midi(f0_hz):
    """Convert Hz to MIDI note, handling unvoiced frames (0 Hz) as NaN."""
    f0_hz = np.asarray(f0_hz)
    midi = np.full_like(f0_hz, np.nan, dtype=float)
    voiced = f0_hz > 0
    midi[voiced] = 69 + 12 * np.log2(f0_hz[voiced] / 440.0)
    return midi

def cents_error(f0_hz, target_hz):
    """Cents error between f0 and target; returns array with NaNs where unvoiced."""
    f0_hz = np.asarray(f0_hz)
    target_hz = np.asarray(target_hz)
    err = np.full_like(f0_hz, np.nan, dtype=float)
    mask = (f0_hz > 0) & (target_hz > 0)
    err[mask] = 1200 * np.log2(f0_hz[mask] / target_hz[mask])
    return err

# -----------------------------------
# Core analysis
# -----------------------------------

def load_audio(path, sr=44100):
    y, sr = librosa.load(path, sr=sr, mono=True)
    return y, sr

def load_midi_notes(path):
    """Return list of (start, end, midi_pitch) for the first melodic track."""
    pm = pretty_midi.PrettyMIDI(path)
    # crude assumption: first instrument is the melody
    instrument = pm.instruments[0]
    notes = []
    for note in instrument.notes:
        notes.append((note.start, note.end, note.pitch))
    # sort by start time
    notes.sort(key=lambda x: x[0])
    return notes

def extract_pitch(y, sr, frame_length=2048, hop_length=256, fmin=80.0, fmax=1000.0):
    """Use librosa YIN to extract f0 contour in Hz."""
    f0 = librosa.yin(
        y,
        fmin=fmin,
        fmax=fmax,
        sr=sr,
        frame_length=frame_length,
        hop_length=hop_length,
    )
    times = librosa.frames_to_time(np.arange(len(f0)), sr=sr, hop_length=hop_length)
    return f0, times

def pitch_to_notes_from_reference(f0, times, min_voiced_hz=50.0, max_gap_sec=0.1):
    """
    Build pseudo-note regions from a reference vocal WAV by grouping voiced frames.
    Returns list of (start, end, midi_pitch).
    """
    f0 = np.asarray(f0)
    times = np.asarray(times)
    voiced_mask = (~np.isnan(f0)) & (f0 > min_voiced_hz)
    if not np.any(voiced_mask):
        return []

    vt = times[voiced_mask]
    vf = f0[voiced_mask]
    vmidi = hz_to_midi(vf)

    boundaries = []
    start_idx = 0
    for i in range(1, len(vt)):
        if vt[i] - vt[i - 1] > max_gap_sec:
            boundaries.append((start_idx, i - 1))
            start_idx = i
    boundaries.append((start_idx, len(vt) - 1))

    notes = []
    for s, e in boundaries:
        seg_midi = vmidi[s:e + 1]
        if seg_midi.size == 0 or np.all(np.isnan(seg_midi)):
            continue
        mean_midi = np.nanmean(seg_midi)
        midi_pitch = int(np.round(mean_midi))
        notes.append((vt[s], vt[e], midi_pitch))
    return notes

def compute_note_level_pitch_stats(f0, times, midi_notes):
    """
    For each reference note, compute:
      - mean cents error
      - std cents error
      - % of frames within +/- 50 cents
    """
    results = []
    for (start, end, midi_pitch) in midi_notes:
        # frames that fall inside this note's time window
        mask = (times >= start) & (times < end)
        if not np.any(mask):
            continue

        note_f0 = f0[mask]
        # target frequency for this note
        target_hz = pretty_midi.note_number_to_hz(midi_pitch)
        target_arr = np.full_like(note_f0, target_hz, dtype=float)
        ce = cents_error(note_f0, target_arr)

        voiced = ~np.isnan(ce)
        if not np.any(voiced):
            continue

        ce_voiced = ce[voiced]
        mean_cents = np.mean(ce_voiced)
        std_cents = np.std(ce_voiced)
        within_50 = np.mean(np.abs(ce_voiced) <= 50) * 100.0

        results.append({
            "start": start,
            "end": end,
            "midi_pitch": midi_pitch,
            "note_name": pretty_midi.note_number_to_name(midi_pitch),
            "mean_cents_error": float(mean_cents),
            "std_cents_error": float(std_cents),
            "percent_within_50_cents": float(within_50),
        })
    return results

def detect_onsets_from_pitch(f0, times, min_silence_hz=50.0):
    """
    Crude onset detection: onset whenever we go from 'unvoiced' to 'voiced'.
    You can swap this for librosa.onset_detect if you want.
    """
    voiced = f0 > min_silence_hz
    onsets = []
    prev_voiced = False
    for i, v in enumerate(voiced):
        if v and not prev_voiced:
            onsets.append(times[i])
        prev_voiced = v
    return np.array(onsets)

def compute_rhythm_stats(onsets, midi_notes):
    """
    Match each reference note to the closest detected onset >= its start time
    and compute ms early/late.
    """
    results = []
    for (start, end, midi_pitch) in midi_notes:
        # pick the earliest onset that falls between start-0.2 and end+0.2 s
        window_mask = (onsets >= (start - 0.2)) & (onsets <= (end + 0.2))
        candidates = onsets[window_mask]
        if len(candidates) == 0:
            timing_error_ms = None
        else:
            # choose onset closest to start time
            idx = np.argmin(np.abs(candidates - start))
            actual_onset = candidates[idx]
            timing_error_ms = (actual_onset - start) * 1000.0

        results.append({
            "start": start,
            "end": end,
            "midi_pitch": midi_pitch,
            "note_name": pretty_midi.note_number_to_name(midi_pitch),
            "timing_error_ms": None if timing_error_ms is None else float(timing_error_ms),
        })

    return results

def summarize_pitch(results):
    all_cents = [r["mean_cents_error"] for r in results]
    all_within_50 = [r["percent_within_50_cents"] for r in results]
    mean_abs_cents = np.mean(np.abs(all_cents))
    overall_within_50 = np.mean(all_within_50)
    return {
        "mean_absolute_cents_error": float(mean_abs_cents),
        "avg_percent_within_50_cents": float(overall_within_50),
    }

def summarize_rhythm(results):
    errors = [r["timing_error_ms"] for r in results if r["timing_error_ms"] is not None]
    if not errors:
        return {
            "mean_abs_timing_error_ms": None,
            "early_fraction": None,
        }
    errors = np.array(errors)
    mean_abs = np.mean(np.abs(errors))
    early_fraction = np.mean(errors < 0)  # < 0 = early
    return {
        "mean_abs_timing_error_ms": float(mean_abs),
        "early_fraction": float(early_fraction),
    }

# -----------------------------------
# Main entry point
# -----------------------------------

def parse_args():
    parser = argparse.ArgumentParser(description="Analyze vocal performance vs reference (MIDI or WAV).")
    parser.add_argument("--audio_path", default="audio/vocal.wav", help="Vocal performance WAV file")
    parser.add_argument("--reference_midi", help="Reference melody MIDI file")
    parser.add_argument("--reference_wav", help="Reference melody WAV file (monophonic)")
    parser.add_argument("--fmin", type=float, default=80.0, help="Minimum f0 (Hz)")
    parser.add_argument("--fmax", type=float, default=1000.0, help="Maximum f0 (Hz)")
    parser.add_argument("--frame_length", type=int, default=2048, help="Frame length for YIN")
    parser.add_argument("--hop_length", type=int, default=256, help="Hop length for YIN")
    return parser.parse_args()


def load_reference_notes(args):
    if args.reference_midi:
        print("Loading MIDI reference...")
        midi_notes = load_midi_notes(args.reference_midi)
        print(f"Loaded {len(midi_notes)} reference notes from {args.reference_midi}")
        return midi_notes, "midi", args.reference_midi
    if args.reference_wav:
        print("Loading reference WAV...")
        y_ref, sr_ref = load_audio(args.reference_wav)
        print(f"Loaded {args.reference_wav} (sr={sr_ref}, duration={len(y_ref)/sr_ref:.2f}s)")
        ref_f0, ref_times = extract_pitch(
            y_ref,
            sr_ref,
            frame_length=args.frame_length,
            hop_length=args.hop_length,
            fmin=args.fmin,
            fmax=args.fmax,
        )
        midi_notes = pitch_to_notes_from_reference(ref_f0, ref_times)
        print(f"Derived {len(midi_notes)} reference notes from WAV")
        return midi_notes, "wav", args.reference_wav
    raise ValueError("You must provide either --reference_midi or --reference_wav")


def main():
    args = parse_args()

    print("Loading audio...")
    y, sr = load_audio(args.audio_path)
    print(f"Loaded {args.audio_path} (sr={sr}, duration={len(y)/sr:.2f}s)")

    midi_notes, ref_type, ref_path = load_reference_notes(args)

    print("Extracting pitch...")
    f0, times = extract_pitch(
        y,
        sr,
        frame_length=args.frame_length,
        hop_length=args.hop_length,
        fmin=args.fmin,
        fmax=args.fmax,
    )
    print(f"Extracted {len(f0)} pitch frames")

    print("Computing note-level pitch stats...")
    pitch_stats = compute_note_level_pitch_stats(f0, times, midi_notes)
    pitch_summary = summarize_pitch(pitch_stats)

    print("\nPitch Summary:")
    print(pitch_summary)

    print("\nFirst 10 notes pitch details:")
    for r in pitch_stats[:10]:
        print(
            f"{r['note_name']:4s} "
            f"start={r['start']:.2f}s "
            f"mean_err={r['mean_cents_error']:+6.1f} cents "
            f"within50={r['percent_within_50_cents']:.1f}%"
        )

    print("\nDetecting onsets and computing rhythm stats...")
    onsets = detect_onsets_from_pitch(f0, times)
    rhythm_stats = compute_rhythm_stats(onsets, midi_notes)
    rhythm_summary = summarize_rhythm(rhythm_stats)

    print("\nRhythm Summary:")
    print(rhythm_summary)

    print("\nFirst 10 notes rhythm details:")
    for r in rhythm_stats[:10]:
        print(
            f"{r['note_name']:4s} "
            f"start={r['start']:.2f}s "
            f"timing_err="
            f"{'None' if r['timing_error_ms'] is None else f'{r['timing_error_ms']:+6.1f} ms'}"
        )

    if ref_type == "wav":
        script_name = os.path.basename(__file__)
        print("\nCommand used (reference WAV):")
        print(f"python {script_name} --audio_path \"{args.audio_path}\" --reference_wav \"{ref_path}\"")

if __name__ == "__main__":
    main()
