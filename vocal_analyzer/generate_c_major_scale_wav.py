import numpy as np
import soundfile as sf
import pretty_midi

SR = 44100
NOTE_LENGTH = 0.6   # seconds per note
GAP = 0.0           # optional silence between notes
AMPLITUDE = 0.3     # keep it under 1.0 to avoid clipping

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
    ascending=True
):
    # C major scale C4–C5
    note_names = ["C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5"]
    if not ascending:
        note_names = list(reversed(note_names))

    midi_notes = [pretty_midi.note_name_to_number(n) for n in note_names]

    audio = []

    for midi_note in midi_notes:
        freq = midi_to_freq(midi_note)
        t = np.linspace(0, NOTE_LENGTH, int(SR * NOTE_LENGTH), endpoint=False)
        # Sine wave
        wave = AMPLITUDE * np.sin(2 * np.pi * freq * t)
        wave = fade_in_out(wave, fade_time=0.01, sr=SR)
        audio.append(wave)

        if GAP > 0:
            gap = np.zeros(int(SR * GAP))
            audio.append(gap)

    audio = np.concatenate(audio).astype(np.float32)

    sf.write(output_path, audio, SR)
    print(f"Wrote {output_path} (duration {len(audio)/SR:.2f}s)")

if __name__ == "__main__":
    generate_c_major_scale_wav()
