import 'package:flutter/foundation.dart' show debugPrint;

import '../models/pitch_highway_difficulty.dart';
import '../models/reference_note.dart';
import '../services/exercise_repository.dart';
import '../services/transposed_exercise_builder.dart';
import '../services/vocal_range_service.dart';
import '../utils/exercise_constants.dart';

/// Service that pre-generates and caches transposed exercises for the current vocal range.
/// Exercises are generated offline when the range is set, allowing instant exercise start.
class ExerciseCacheService {
  static final ExerciseCacheService instance = ExerciseCacheService._();
  ExerciseCacheService._();

  final ExerciseRepository _exerciseRepo = ExerciseRepository();
  final VocalRangeService _rangeService = VocalRangeService();

  // Cache: exerciseId -> (difficulty -> notes)
  // For exercises without difficulty, use null as the key
  final Map<String, Map<String?, List<ReferenceNote>>> _cache = {};
  int? _cachedLowestMidi;
  int? _cachedHighestMidi;
  bool _isGenerating = false;

  /// Get cached notes for an exercise. Returns null if not cached or range changed.
  List<ReferenceNote>? getCachedNotes({
    required String exerciseId,
    PitchHighwayDifficulty? difficulty,
  }) {
    final difficultyKey = difficulty?.name;
    final exerciseCache = _cache[exerciseId];
    if (exerciseCache == null) return null;
    return exerciseCache[difficultyKey];
  }

  /// Check if cache is valid for the current range
  bool isCacheValid() {
    if (_cachedLowestMidi == null || _cachedHighestMidi == null) {
      return false;
    }
    // Cache is valid if range hasn't changed
    return true;
  }

  /// Get the current cached range
  (int?, int?) getCachedRange() {
    return (_cachedLowestMidi, _cachedHighestMidi);
  }

  /// Generate and cache all exercises for the given range.
  /// This should be called when the range is set or changes.
  Future<void> generateCache({
    required int lowestMidi,
    required int highestMidi,
  }) async {
    if (_isGenerating) {
      debugPrint('[ExerciseCacheService] Already generating, skipping');
      return;
    }

    // Skip if range hasn't changed
    if (_cachedLowestMidi == lowestMidi && _cachedHighestMidi == highestMidi) {
      debugPrint('[ExerciseCacheService] Range unchanged, skipping cache generation');
      return;
    }

    _isGenerating = true;
    debugPrint('[ExerciseCacheService] Generating cache for range: $lowestMidi-$highestMidi');

    try {
      final exercises = _exerciseRepo.getExercises();
      _cache.clear();

      // Generate for each exercise
      for (final exercise in exercises) {
        // Only cache exercises with highwaySpec (pitch highway exercises)
        if (exercise.highwaySpec == null || exercise.highwaySpec!.segments.isEmpty) {
          continue;
        }

        // Generate for each difficulty level
        for (final difficulty in PitchHighwayDifficulty.values) {
          final notes = TransposedExerciseBuilder.buildTransposedSequence(
            exercise: exercise,
            lowestMidi: lowestMidi,
            highestMidi: highestMidi,
            leadInSec: ExerciseConstants.leadInSec,
            difficulty: difficulty,
          );

          final difficultyKey = difficulty.name;
          if (!_cache.containsKey(exercise.id)) {
            _cache[exercise.id] = {};
          }
          _cache[exercise.id]![difficultyKey] = notes;
        }

        // Also generate without difficulty (default)
        final notesDefault = TransposedExerciseBuilder.buildTransposedSequence(
          exercise: exercise,
          lowestMidi: lowestMidi,
          highestMidi: highestMidi,
          leadInSec: ExerciseConstants.leadInSec,
          difficulty: null,
        );

        if (!_cache.containsKey(exercise.id)) {
          _cache[exercise.id] = {};
        }
        _cache[exercise.id]![null] = notesDefault;
      }

      _cachedLowestMidi = lowestMidi;
      _cachedHighestMidi = highestMidi;
      debugPrint('[ExerciseCacheService] Cache generation complete: ${_cache.length} exercises cached');
    } catch (e, stackTrace) {
      debugPrint('[ExerciseCacheService] Error generating cache: $e');
      debugPrint('[ExerciseCacheService] Stack trace: $stackTrace');
    } finally {
      _isGenerating = false;
    }
  }

  /// Load cache for the current range (if range is set).
  /// Call this on app startup.
  Future<void> loadCache() async {
    final (lowestMidi, highestMidi) = await _rangeService.getRange();
    // getRange() always returns valid values (uses defaults if not set)
    await generateCache(lowestMidi: lowestMidi, highestMidi: highestMidi);
  }

  /// Clear the cache (e.g., when range is cleared)
  void clearCache() {
    _cache.clear();
    _cachedLowestMidi = null;
    _cachedHighestMidi = null;
    debugPrint('[ExerciseCacheService] Cache cleared');
  }
}
