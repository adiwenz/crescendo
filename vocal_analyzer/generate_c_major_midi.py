import pretty_midi

def generate_c_major_scale(
    output_path="c_major_scale.mid",
    start_time=0.0,
    note_length=0.6,
    velocity=90
):
    # C major scale: C D E F G A B C
    # Using octave 4 → 5
    scale_pitches = [
        pretty_midi.note_name_to_number(n)
        for n in ["C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5"]
    ]

    # Create MIDI object
    pm = pretty_midi.PrettyMIDI()

    # Add an instrument (0 = Acoustic Grand Piano)
    instrument = pretty_midi.Instrument(program=0)

    time = start_time

    for pitch in scale_pitches:
        note = pretty_midi.Note(
            velocity=velocity,
            pitch=pitch,
            start=time,
            end=time + note_length
        )
        instrument.notes.append(note)
        time += note_length

    pm.instruments.append(instrument)
    pm.write(output_path)

    print(f"Created MIDI: {output_path}")


if __name__ == "__main__":
    generate_c_major_scale()