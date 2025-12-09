import argparse
import csv
import math

from typing import List, Dict

import numpy as np
import librosa


def hz_to_cents_error(measured_hz: float, target_hz: float) -> float:
    """
    Returns cents difference between measured_hz and target_hz.
    Positive = sharp, negative = flat.
    """
    if measured_hz <= 0 or target_hz <= 0:
        return 0.0
    return 1200.0 * math.log2(measured_hz / target_hz)


def detect_notes_from_f0(
    f0: np.ndarray,
    times: np.ndarray,
    sr: int,
    hop_length: int,
    min_note_len_frames: int = 5,
) -> List[Dict]:
    """
    Group contiguous voiced frames into "notes".

    f0: array of fundamental frequency per frame (Hz, np.nan for unvoiced)
    times: array of times (seconds) per frame
    sr: sample rate
    hop_length: hop length used for analysis
    min_note_len_frames: minimum frames to consider a valid note
    """
    notes = []

    current_idxs = []

    def flush_current():
        nonlocal current_idxs
        if len(current_idxs) < min_note_len_frames:
            current_idxs = []
            return

        idxs = np.array(current_idxs)
        f0_vals = f0[idxs]
        time_vals = times[idxs]

        # Use median to be robust against outliers
        measured_hz = float(np.median(f0_vals))

        # Map to nearest MIDI note
        midi = float(librosa.hz_to_midi(measured_hz))
        midi_rounded = int(round(midi))
        target_hz = float(librosa.midi_to_hz(midi_rounded))
        note_name = librosa.midi_to_note(midi_rounded)

        start_time = float(time_vals[0])
        end_time = float(time_vals[-1])
        duration = end_time - start_time

        cents_error = hz_to_cents_error(measured_hz, target_hz)

        note = {
            "start_time": start_time,
            "end_time": end_time,
            "duration": duration,
            "note_name": note_name,
            "measured_hz": measured_hz,
            "target_hz": target_hz,
            "cents_error": cents_error,
        }
        notes.append(note)
        current_idxs = []

    for i, freq in enumerate(f0):
        if np.isnan(freq) or freq <= 0:
            # unvoiced
            if current_idxs:
                flush_current()
            continue

        # voiced
        if not current_idxs:
            current_idxs = [i]
        else:
            # continue current note
            current_idxs.append(i)

    # flush tail
    if current_idxs:
        flush_current()

    return notes


def analyze_audio_to_take(
    audio_path: str,
    take_name: str,
    output_csv: str,
    fmin: str = "C2",
    fmax: str = "C7",
    frame_length: int = 2048,
    hop_length: int = 256,
):
    """
    - Loads audio file
    - Runs YIN f0 estimation
    - Groups frames into notes
    - Writes a Melodyne-style CSV for this take
    """
    print(f"Loading audio: {audio_path}")
    y, sr = librosa.load(audio_path, sr=None, mono=True)

    print("Estimating pitch (YIN)...")
    f0 = librosa.yin(
        y,
        fmin=librosa.note_to_hz(fmin),
        fmax=librosa.note_to_hz(fmax),
        frame_length=frame_length,
        hop_length=hop_length,
    )

    # YIN returns frequency for each frame; get corresponding times
    times = librosa.frames_to_time(
        np.arange(len(f0)), sr=sr, hop_length=hop_length
    )

    # YIN sometimes outputs out-of-range / zero; treat negatives as unvoiced
    f0 = np.where(f0 > 0, f0, np.nan)

    print("Grouping frames into notes...")
    notes = detect_notes_from_f0(f0, times, sr, hop_length)

    print(f"Detected {len(notes)} notes.")

    # Write CSV
    fieldnames = [
        "take",
        "note_index",
        "start_time",
        "end_time",
        "duration",
        "note_name",
        "measured_hz",
        "target_hz",
        "cents_error",
    ]

    print(f"Writing CSV: {output_csv}")
    with open(output_csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()

        for idx, note in enumerate(notes):
            row = {
                "take": take_name,
                "note_index": idx,
                "start_time": note["start_time"],
                "end_time": note["end_time"],
                "duration": note["duration"],
                "note_name": note["note_name"],
                "measured_hz": note["measured_hz"],
                "target_hz": note["target_hz"],
                "cents_error": note["cents_error"],
            }
            writer.writerow(row)

    print("✅ Done.")


def main():
    parser = argparse.ArgumentParser(
        description="Generate a 'take' CSV from an audio clip."
    )
    parser.add_argument("audio", help="Path to mono vocal audio file (e.g., .wav)")
    parser.add_argument(
        "--take_name",
        default=None,
        help="Name for the take (default: audio filename without extension)",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Output CSV path (default: takes/<take_name>.csv)",
    )
    parser.add_argument(
        "--fmin",
        default="C2",
        help="Minimum note for pitch detection (default: C2)",
    )
    parser.add_argument(
        "--fmax",
        default="C7",
        help="Maximum note for pitch detection (default: C7)",
    )
    args = parser.parse_args()

    import os

    audio_path = args.audio
    base = os.path.splitext(os.path.basename(audio_path))[0]

    take_name = args.take_name or base
    output_csv = args.output or os.path.join("takes", f"{take_name}.csv")

    # Make sure takes/ exists if using default
    os.makedirs(os.path.dirname(output_csv), exist_ok=True)

    analyze_audio_to_take(
        audio_path=audio_path,
        take_name=take_name,
        output_csv=output_csv,
        fmin=args.fmin,
        fmax=args.fmax,
    )


if __name__ == "__main__":
    main()