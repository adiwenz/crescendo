import 'package:flutter/foundation.dart';
import 'preview_spec.dart';

/// Service that maps exercise IDs to preview audio asset paths.
/// 
/// NOTE: Non-glide exercises now use MIDI previews (generated at runtime).
/// Only glide exercises use WAV assets (or real-time sine sweep for NG Slides).
/// 
/// This is a compatibility wrapper around PreviewSpecRegistry.
class PreviewAssetService {
  /// Maps exercise ID to preview asset path (WAV files only).
  /// Returns null if exercise uses MIDI previews, real-time generation (NG Slides), or has no preview.
  static String? getPreviewAssetPath(String exerciseId) {
    return PreviewSpecRegistry.getPreviewAssetPath(exerciseId);
  }

  /// Check if an exercise has a preview (MIDI or WAV).
  /// Returns true for exercises that have previews (either MIDI or WAV).
  static bool hasPreview(String exerciseId) {
    // All exercises with highwaySpec should have previews (either MIDI or WAV)
    // This is a simple check - in practice, PreviewAudioService routes based on isGlide
    return PreviewSpecRegistry.hasPreview(exerciseId) || _hasMidiPreview(exerciseId);
  }

  /// Check if an exercise uses MIDI preview (non-glide exercises)
  static bool _hasMidiPreview(String exerciseId) {
    // List of known non-glide exercises that use MIDI previews
    const midiPreviewExercises = {
      'five_tone_scales',
      'vv_zz_scales',
      'humming_scales',
      'chest_voice_scales',
      'head_voice_scales',
      'scale_degrees',
      'forward_placement',
      'mask_resonance',
      'arpeggios',
      'mix_bridging',
      'sustained_s_z',
      'lip_trills',
      'sustained_pitch_holds',
      'fast_three_note_patterns',
      'staccato_bursts',
      'descending_runs',
      'interval_training',
      'descending_head_to_chest',
    };
    return midiPreviewExercises.contains(exerciseId);
  }

  /// Log missing asset (called when asset fails to load).
  static void logMissingAsset(String assetPath) {
    if (kDebugMode) {
      debugPrint('[PreviewAudio] missing asset: $assetPath');
    }
  }
}
