import 'package:flutter/foundation.dart';
import 'preview_spec.dart';

/// Service that maps exercise IDs to preview audio asset paths.
/// All previews use pre-baked WAV files except NG Slides (real-time sine sweep).
/// This is a compatibility wrapper around PreviewSpecRegistry.
class PreviewAssetService {
  /// Maps exercise ID to preview asset path.
  /// Returns null if exercise should use real-time generation (NG Slides) or has no preview.
  static String? getPreviewAssetPath(String exerciseId) {
    return PreviewSpecRegistry.getPreviewAssetPath(exerciseId);
  }

  /// Check if an exercise has a preview asset (or uses real-time generation).
  static bool hasPreview(String exerciseId) {
    return PreviewSpecRegistry.hasPreview(exerciseId);
  }

  /// Log missing asset (called when asset fails to load).
  static void logMissingAsset(String assetPath) {
    if (kDebugMode) {
      debugPrint('[PreviewAudio] missing asset: $assetPath');
    }
  }
}
