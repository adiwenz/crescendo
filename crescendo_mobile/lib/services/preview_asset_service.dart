import 'package:flutter/foundation.dart';

/// Service that maps exercise IDs to preview audio asset paths.
/// All previews use pre-baked WAV files except NG Slides (real-time sine sweep).
class PreviewAssetService {
  static const String _basePath = 'assets/audio/previews/';
  
  /// Asset paths for each preview type
  static const String sirenPreview = '${_basePath}siren_preview.wav';
  static const String scalesPreview = '${_basePath}scales_preview.wav';
  static const String arpeggioPreview = '${_basePath}arpeggio_preview.wav';
  static const String slidesPreview = '${_basePath}slides_preview.wav';
  static const String warmupPreview = '${_basePath}warmup_preview.wav';
  static const String agilityPreview = '${_basePath}agility_preview.wav';

  /// Maps exercise ID to preview asset path.
  /// Returns null if exercise should use real-time generation (NG Slides) or has no preview.
  static String? getPreviewAssetPath(String exerciseId) {
    switch (exerciseId) {
      case 'sirens':
        return sirenPreview;
      
      // Scale exercises
      case 'vv_zz_scales':
      case 'humming_scales':
      case 'five_tone_scales':
      case 'chest_voice_scales':
      case 'head_voice_scales':
      case 'scale_degrees':
        return scalesPreview;
      
      // Arpeggio exercises
      case 'arpeggios':
        return arpeggioPreview;
      
      // Slide exercises (octave slides, but NOT ng_slides - that uses real-time)
      case 'octave_slides':
        return slidesPreview;
      
      // Warmup exercises
      case 'yawn_sigh':
      case 'sustained_s_z':
      case 'lip_trills':
        return warmupPreview;
      
      // Agility exercises
      case 'fast_three_note_patterns':
      case 'staccato_bursts':
      case 'descending_runs':
        return agilityPreview;
      
      // Sustained pitch holds
      case 'sustained_pitch_holds':
        return warmupPreview; // Use warmup preview (sustained tone)
      
      // Interval training
      case 'interval_training':
        return scalesPreview; // Use scales preview (interval pattern)
      
      // NG Slides: special case - uses real-time sine sweep, NOT a WAV file
      case 'ng_slides':
        return null; // Signal to use real-time generation
      
      default:
        return null; // No preview available
    }
  }

  /// Check if an exercise has a preview asset (or uses real-time generation).
  static bool hasPreview(String exerciseId) {
    return getPreviewAssetPath(exerciseId) != null || exerciseId == 'ng_slides';
  }

  /// Log missing asset (called when asset fails to load).
  static void logMissingAsset(String assetPath) {
    if (kDebugMode) {
      debugPrint('[PreviewAudio] missing asset: $assetPath');
    }
  }
}
