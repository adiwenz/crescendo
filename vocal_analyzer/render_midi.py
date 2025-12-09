from midi2audio import FluidSynth

# You may need to specify a soundfont -- macOS usually has this one:
soundfont = "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.sf2"

fs = FluidSynth(soundfont)
fs.midi_to_audio("audio/reference.mid", "audio/reference.wav")

print("Rendered to audio/reference.wav")
