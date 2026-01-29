# SoundFont Assets

This directory should contain SoundFont (.sf2) files for MIDI synthesis.

## Required File

Place a SoundFont file named `default.sf2` in this directory.

## Recommended SoundFonts

For a good quality, license-compatible SoundFont, consider:

1. **FluidR3_GM.sf2** - General MIDI SoundFont (public domain)
   - Download from: https://member.keymusician.com/Member/FluidR3_GM/index.html
   - Or search for "FluidR3_GM.sf2" (public domain)

2. **Timbres of Heaven** - High quality GM SoundFont
   - Check license before use

3. **Musescore General** - From Musescore project
   - Check license before use

## Installation

1. Download a SoundFont file (.sf2 format)
2. Rename it to `default.sf2`
3. Place it in this directory (`assets/soundfonts/default.sf2`)
4. The app will automatically load it for MIDI rendering

## Note

If no SoundFont is provided, the app will fall back to software synthesis (oscillator-based) for glides, which may have pops on ascending glides.
