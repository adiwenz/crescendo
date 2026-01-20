/// Specification for a preview audio asset
class PreviewSpec {
  /// Asset path relative to assets/audio/previews/
  final String assetPath;
  
  /// Duration in seconds (for validation)
  final double durationSeconds;
  
  /// Description of what the preview contains
  final String description;

  const PreviewSpec({
    required this.assetPath,
    required this.durationSeconds,
    required this.description,
  });
}

/// Centralized mapping of exercise IDs to preview specifications
class PreviewSpecRegistry {
  static const String _basePath = 'assets/audio/previews/';

  /// Preview specifications for each preview type
  static const PreviewSpec sirenPreview = PreviewSpec(
    assetPath: '${_basePath}siren_preview.wav',
    durationSeconds: 4.0,
    description: 'Bell curve glide (up then down), no tail',
  );

  static const PreviewSpec fiveToneScalePreview = PreviewSpec(
    assetPath: '${_basePath}five_tone_scale_preview.wav',
    durationSeconds: 2.5,
    description: 'Five notes: Do-Re-Mi-Fa-Sol (C4-D4-E4-F4-G4)',
  );

  static const PreviewSpec arpeggioPreview = PreviewSpec(
    assetPath: '${_basePath}arpeggio_preview.wav',
    durationSeconds: 2.0,
    description: 'Arpeggiated chord pattern',
  );

  static const PreviewSpec slidesPreview = PreviewSpec(
    assetPath: '${_basePath}slides_preview.wav',
    durationSeconds: 1.5,
    description: 'Upward glide (octave slide)',
  );

  static const PreviewSpec warmupPreview = PreviewSpec(
    assetPath: '${_basePath}warmup_preview.wav',
    durationSeconds: 3.0,
    description: 'Sustained tone',
  );

  static const PreviewSpec agilityPreview = PreviewSpec(
    assetPath: '${_basePath}agility_preview.wav',
    durationSeconds: 1.5,
    description: 'Fast three-note pattern',
  );

  static const PreviewSpec yawnSighPreview = PreviewSpec(
    assetPath: '${_basePath}yawn_sigh_preview.wav',
    durationSeconds: 2.0,
    description: 'Descending glide (smooth downward sweep)',
  );

  static const PreviewSpec intervalPreview = PreviewSpec(
    assetPath: '${_basePath}interval_preview.wav',
    durationSeconds: 1.5,
    description: 'Interval demo: Do then Sol (C4 then G4)',
  );

  static const PreviewSpec descendingOctavePreview = PreviewSpec(
    assetPath: '${_basePath}descending_octave_preview.wav',
    durationSeconds: 3.5,
    description: 'Descending octave scale (C5 down to C4)',
  );

  /// Maps exercise ID to preview specification
  /// 
  /// NOTE: This is now primarily for GLIDE exercises (isGlide == true).
  /// Non-glide exercises use MIDI previews generated at runtime (see MidiPreviewGenerator).
  /// 
  /// Returns null if exercise has no preview, uses real-time generation, or uses MIDI previews.
  static PreviewSpec? getPreviewSpec(String exerciseId) {
    switch (exerciseId) {
      // GLIDE EXERCISES (use WAV previews):
      
      // Sirens: bell curve, no tail
      case 'sirens':
        return sirenPreview;

      // Slide exercises (octave slides)
      case 'octave_slides':
        return slidesPreview;

      // Yawn-Sigh (descending glide)
      case 'yawn_sigh':
        return yawnSighPreview;

      // NG Slides: special case - uses real-time sine sweep, NOT a WAV file
      case 'ng_slides':
        return null; // Signal to use real-time generation

      // NON-GLIDE EXERCISES (use MIDI previews - return null here):
      // These exercises now use MidiPreviewGenerator to generate previews at C4:
      // - five_tone_scales, vv_zz_scales, humming_scales
      // - chest_voice_scales, head_voice_scales, scale_degrees
      // - forward_placement, mask_resonance
      // - arpeggios, mix_bridging
      // - sustained_s_z, lip_trills, sustained_pitch_holds
      // - fast_three_note_patterns, staccato_bursts, descending_runs
      // - interval_training
      // - descending_head_to_chest
      // All return null - they use MIDI previews instead

      default:
        return null; // No preview available or uses MIDI preview
    }
  }

  /// Get asset path for an exercise (convenience method)
  static String? getPreviewAssetPath(String exerciseId) {
    return getPreviewSpec(exerciseId)?.assetPath;
  }

  /// Check if an exercise has a preview asset (or uses real-time generation)
  static bool hasPreview(String exerciseId) {
    return getPreviewSpec(exerciseId) != null || exerciseId == 'ng_slides';
  }
}
