import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'exercise_audio_asset_resolver.dart';

/// Service for slicing full-range exercise audio based on user's vocal range.
/// 
/// Uses the JSON index to determine which time range to play for a given
/// user range (lowestMidi, highestMidi).
class ExerciseAudioSlicer {
  static final ExerciseAudioSlicer instance = ExerciseAudioSlicer._();
  ExerciseAudioSlicer._();

  // Cache loaded indices
  final Map<String, Map<String, dynamic>> _indexCache = {};

  /// Get slice parameters for an exercise given user's vocal range.
  /// 
  /// Returns (sliceStartSec, sliceEndSec) or null if no valid slice found.
  Future<({double startSec, double endSec})?> getSlice({
    required String exerciseId,
    required int lowestMidi,
    required int highestMidi,
  }) async {
    try {
      // Load index (cached)
      final index = await _loadIndex(exerciseId);
      if (index == null) {
        if (kDebugMode) {
          debugPrint('[ExerciseAudioSlicer] No index found for $exerciseId');
        }
        return null;
      }

      final steps = index['steps'] as List<dynamic>?;
      if (steps == null || steps.isEmpty) {
        if (kDebugMode) {
          debugPrint('[ExerciseAudioSlicer] No steps in index for $exerciseId');
        }
        return null;
      }

      // Find first step that starts at or above lowestMidi
      int firstStepIndex = -1;
      for (var i = 0; i < steps.length; i++) {
        final step = steps[i] as Map<String, dynamic>;
        final rootMidi = step['rootMidi'] as int;
        if (rootMidi >= lowestMidi) {
          firstStepIndex = i;
          break;
        }
      }

      // If no step found, use the last step
      if (firstStepIndex == -1) {
        firstStepIndex = steps.length - 1;
      }

      // Find last step that ends at or below highestMidi
      int lastStepIndex = -1;
      for (var i = steps.length - 1; i >= 0; i--) {
        final step = steps[i] as Map<String, dynamic>;
        final rootMidi = step['rootMidi'] as int;
        if (rootMidi <= highestMidi) {
          lastStepIndex = i;
          break;
        }
      }

      // If no step found, use the first step
      if (lastStepIndex == -1) {
        lastStepIndex = 0;
      }

      // Ensure valid range
      if (firstStepIndex > lastStepIndex) {
        // Swap if needed
        final temp = firstStepIndex;
        firstStepIndex = lastStepIndex;
        lastStepIndex = temp;
      }

      final firstStep = steps[firstStepIndex] as Map<String, dynamic>;
      final lastStep = steps[lastStepIndex] as Map<String, dynamic>;

      final sliceStartSec = firstStep['startSec'] as double;
      final sliceEndSec = lastStep['endSec'] as double;

      if (kDebugMode) {
        debugPrint('[ExerciseAudioSlicer] Slice for $exerciseId (range: $lowestMidi-$highestMidi):');
        debugPrint('  Steps: ${firstStepIndex + 1}-${lastStepIndex + 1} of ${steps.length}');
        debugPrint('  Time: ${sliceStartSec.toStringAsFixed(2)}s - ${sliceEndSec.toStringAsFixed(2)}s');
      }

      return (startSec: sliceStartSec, endSec: sliceEndSec);
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[ExerciseAudioSlicer] Error getting slice: $e');
        debugPrint('[ExerciseAudioSlicer] Stack trace: $stackTrace');
      }
      return null;
    }
  }

  /// Get slice for preview (single step at C4 / MIDI 60)
  Future<({double startSec, double endSec})?> getPreviewSlice(String exerciseId) async {
    return getSlice(
      exerciseId: exerciseId,
      lowestMidi: 60,
      highestMidi: 60,
    );
  }

  Future<Map<String, dynamic>?> _loadIndex(String exerciseId) async {
    if (_indexCache.containsKey(exerciseId)) {
      return _indexCache[exerciseId];
    }

    try {
      final index = await ExerciseAudioAssetResolver.loadIndex(exerciseId);
      _indexCache[exerciseId] = index;
      return index;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ExerciseAudioSlicer] Failed to load index for $exerciseId: $e');
      }
      return null;
    }
  }

  /// Clear the index cache (useful for testing or reloading)
  void clearCache() {
    _indexCache.clear();
  }
}
