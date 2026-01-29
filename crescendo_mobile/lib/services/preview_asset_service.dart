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
    return PreviewSpecRegistry.hasPreview(exerciseId);
  }



  /// Log missing asset (called when asset fails to load).
  static void logMissingAsset(String assetPath) {
    if (kDebugMode) {
      debugPrint('[PreviewAudio] missing asset: $assetPath');
    }
  }
}
