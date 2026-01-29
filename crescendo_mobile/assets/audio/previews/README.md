# Preview Audio Assets

This directory contains pre-generated WAV files for exercise previews. These files are bundled with the app and loaded instantly when users tap the preview button.

## Files

- `siren_preview.wav` - Continuous bell curve glide (up then down) for Sirens exercise
- `scales_preview.wav` - Ascending scale pattern for scale exercises
- `arpeggio_preview.wav` - Arpeggiated chord pattern for arpeggio exercises
- `slides_preview.wav` - Upward glide for octave slide exercises
- `warmup_preview.wav` - Sustained tone for warmup exercises
- `agility_preview.wav` - Fast three-note pattern for agility exercises

## Generating Assets

To regenerate these files, run:

```bash
dart tool/generate_preview_assets.dart
```

This script will:
1. Generate all preview WAV files
2. Write them to `assets/audio/previews/`
3. Use 44.1kHz sample rate, 16-bit PCM, mono
4. Normalize volume to safe levels (no clipping)

## Special Cases

- **NG Slides**: Does NOT use a bundled WAV file. Instead, it generates a real-time sine sweep when preview is tapped. This is handled by `PreviewAudioService`.

## Notes

- These files are committed to git and bundled with the app
- Do NOT generate these at runtime - they should be pre-baked
- If a preview asset is missing, the app will log a warning and fail silently (no crash)
