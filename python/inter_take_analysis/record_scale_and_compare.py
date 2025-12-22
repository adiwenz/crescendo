#!/usr/bin/env python3
"""
Generate a C-major scale reference, play it while recording, then update analysis_similarity.json.

Steps:
1) Synthesize a C-major scale WAV at a given BPM and note length (beats per note).
2) Play the scale and record mic simultaneously.
3) Save reference and vocal WAVs to audio_files/.
4) Run analyze_vocal -> append/update take in vocal_analyzer/analysis_similarity.json.

Requires: sounddevice, soundfile, numpy.
"""
import argparse
import math
import time
from pathlib import Path
import numpy as np
import sounddevice as sd
import soundfile as sf
import subprocess

ROOT = Path(__file__).resolve().parent.parent
AUDIO_DIR = ROOT / "audio_files"
SIM_JSON = ROOT / "vocal_analyzer" / "analysis_similarity.json"


def midi_to_hz(m):
    return 440.0 * (2 ** ((m - 69) / 12))


def synth_c_major(bpm: float, beats_per_note: float, sr: int = 44100, amp: float = 0.3):
    # C4..C5 inclusive (8 notes)
    midi_notes = [60, 62, 64, 65, 67, 69, 71, 72]
    note_dur = 60.0 / bpm * beats_per_note
    fade = 0.01
    audio = []
    for m in midi_notes:
        t = np.linspace(0, note_dur, int(sr * note_dur), endpoint=False)
        env = np.ones_like(t)
        fade_samp = max(1, int(fade * sr))
        env[:fade_samp] *= np.linspace(0, 1, fade_samp)
        env[-fade_samp:] *= np.linspace(1, 0, fade_samp)
        tone = amp * env * np.sin(2 * np.pi * midi_to_hz(m) * t)
        audio.append(tone)
    audio = np.concatenate(audio)
    return audio, note_dur * len(midi_notes)


def play_and_record(reference: np.ndarray, sr: int = 44100):
    """Play reference mono audio and record mic at the same time (blocking)."""
    ref = reference.reshape(-1, 1)
    recording = sd.playrec(ref, samplerate=sr, channels=1, blocking=True)
    return recording.squeeze()


def run_similarity(vocal_path: Path, ref_path: Path, take: str):
    cmd = [
        "python",
        str(ROOT / "vocal_analyzer" / "update_analysis_similarity.py"),
        "--vocal",
        str(vocal_path),
        "--reference",
        str(ref_path),
        "--take_name",
        take,
        "--json_out",
        str(SIM_JSON),
    ]
    subprocess.run(cmd, check=True, cwd=ROOT)


def main():
    ap = argparse.ArgumentParser(description="Generate C scale, record mic, and compare to reference.")
    ap.add_argument("--take_name", default=None, help="Take name (default: scale_<timestamp>)")
    ap.add_argument("--bpm", type=float, default=90.0, help="Tempo for the scale")
    ap.add_argument("--beats_per_note", type=float, default=1.0, help="Beats per note (default quarter-note)")
    ap.add_argument("--samplerate", type=int, default=44100)
    args = ap.parse_args()

    take = args.take_name or f"scale_{int(time.time())}"
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)

    ref_audio, ref_dur = synth_c_major(args.bpm, args.beats_per_note, sr=args.samplerate)
    ref_path = AUDIO_DIR / f"{take}_ref.wav"
    sf.write(ref_path, ref_audio, args.samplerate)
    print(f"Reference saved to {ref_path} ({ref_dur:.2f}s)")

    print("Playing scale and recording mic...")
    vocal_audio = play_and_record(ref_audio, sr=args.samplerate)
    vocal_path = AUDIO_DIR / f"{take}.wav"
    sf.write(vocal_path, vocal_audio, args.samplerate)
    print(f"Recorded vocal saved to {vocal_path}")

    print("Running similarity analysis...")
    run_similarity(vocal_path, ref_path, take)
    print(f"✅ Updated {SIM_JSON} with take '{take}'")


if __name__ == "__main__":
    main()
