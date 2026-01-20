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
  /// Returns null if exercise has no preview or uses real-time generation
  static PreviewSpec? getPreviewSpec(String exerciseId) {
    switch (exerciseId) {
      // Sirens: bell curve, no tail
      case 'sirens':
        return sirenPreview;

      // 5-tone scale exercises (5 notes only, not full octave)
      case 'five_tone_scales':
      case 'vv_zz_scales':
      case 'humming_scales':
      case 'chest_voice_scales':
      case 'head_voice_scales':
        return fiveToneScalePreview;

      // Arpeggio exercises
      case 'arpeggios':
        return arpeggioPreview;

      // Slide exercises (octave slides, but NOT ng_slides - that uses real-time)
      case 'octave_slides':
        return slidesPreview;

      // Warmup exercises (sustained tone)
      case 'sustained_s_z':
      case 'lip_trills':
      case 'sustained_pitch_holds':
        return warmupPreview;

      // Agility exercises
      case 'fast_three_note_patterns':
      case 'staccato_bursts':
      case 'descending_runs':
        return agilityPreview;

      // YawnSigh: descending glide
      case 'yawn_sigh':
        return yawnSighPreview;

      // Interval training: Do->Sol interval
      case 'interval_training':
        return intervalPreview;

      // Descending head to chest: descending octave scale
      case 'descending_head_to_chest':
        return descendingOctavePreview;

      // Forward Placement (Nay/Nee): 5-tone scale
      case 'forward_placement':
        return fiveToneScalePreview;

      // Mask Resonance Buzz: 5-tone scale
      case 'mask_resonance':
        return fiveToneScalePreview;

      // Mix Bridging: arpeggio pattern
      case 'mix_bridging':
        return arpeggioPreview;

      // Scale Degrees: 5-tone scale
      case 'scale_degrees':
        return fiveToneScalePreview;

      // NG Slides: special case - uses real-time sine sweep, NOT a WAV file
      case 'ng_slides':
        return null; // Signal to use real-time generation

      default:
        return null; // No preview available
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
