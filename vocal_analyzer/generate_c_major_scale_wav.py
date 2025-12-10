import argparse
import numpy as np
import soundfile as sf
import pretty_midi

SR = 44100
DEFAULT_NOTE_LENGTH = 0.5   # seconds per note
DEFAULT_GAP = 0.08          # short pause between notes
DEFAULT_AMPLITUDE = 0.35    # keep it under 1.0 to avoid clipping

def midi_to_freq(midi_note):
    return 440.0 * 2 ** ((midi_note - 69) / 12.0)

def fade_in_out(wave, fade_time=0.01, sr=SR):
    """Apply short fade-in and fade-out to avoid clicks."""
    n_fade = int(fade_time * sr)
    if n_fade == 0 or len(wave) < 2 * n_fade:
        return wave

    window = np.ones_like(wave)
    fade_in = np.linspace(0.0, 1.0, n_fade)
    fade_out = np.linspace(1.0, 0.0, n_fade)
    window[:n_fade] = fade_in
    window[-n_fade:] = fade_out
    return wave * window

def generate_c_major_scale_wav(
    output_path="audio/c_major_scale.wav",
    ascending=True,
    note_length=DEFAULT_NOTE_LENGTH,
    gap=DEFAULT_GAP,
    amplitude=DEFAULT_AMPLITUDE,
    sr=SR,
):
    # C major scale C4–C5
    note_names = ["C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5"]
    if not ascending:
        note_names = list(reversed(note_names))

    midi_notes = [pretty_midi.note_name_to_number(n) for n in note_names]

    audio = []

    for midi_note in midi_notes:
        freq = midi_to_freq(midi_note)
        t = np.linspace(0, note_length, int(sr * note_length), endpoint=False)

        # Piano-ish tone: a few harmonics with exponential decay and fast attack
        env = np.exp(-t / 0.6)  # decay envelope
        harmonics = [1.0, 0.5, 0.25, 0.12]
        wave = np.zeros_like(t)
        for h_idx, amp_h in enumerate(harmonics, start=1):
            wave += amp_h * np.sin(2 * np.pi * freq * h_idx * t)
        wave = amplitude * env * wave / np.max(np.abs(wave) + 1e-9)
        wave = fade_in_out(wave, fade_time=0.01, sr=sr)
        audio.append(wave)

        if gap > 0:
            audio.append(np.zeros(int(sr * gap)))

    audio = np.concatenate(audio).astype(np.float32)

    sf.write(output_path, audio, sr)
    print(f"Wrote {output_path} (duration {len(audio)/sr:.2f}s)")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate a simple C major scale WAV.")
    parser.add_argument("--output", default="audio/c_major_scale.wav", help="Output WAV path")
    parser.add_argument("--descending", action="store_true", help="Generate descending scale instead of ascending")
    parser.add_argument("--note_length", type=float, default=DEFAULT_NOTE_LENGTH, help="Length of each note in seconds")
    parser.add_argument("--gap", type=float, default=DEFAULT_GAP, help="Silence gap between notes in seconds")
    parser.add_argument("--amplitude", type=float, default=DEFAULT_AMPLITUDE, help="Amplitude scale (0-1)")
    args = parser.parse_args()

    generate_c_major_scale_wav(
        output_path=args.output,
        ascending=not args.descending,
        note_length=args.note_length,
        gap=args.gap,
        amplitude=args.amplitude,
    )
