import 'package:flutter/foundation.dart' show compute, debugPrint;

import '../audio/ref_audio/wav_cache_manager.dart';

import '../models/pitch_highway_difficulty.dart';
import '../models/reference_note.dart';
import '../services/exercise_repository.dart';
import '../services/transposed_exercise_builder.dart';
import '../services/vocal_range_service.dart';
import '../utils/audio_constants.dart';

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
  /// This runs in a background isolate to avoid blocking the main UI thread.
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
    debugPrint('[ExerciseCacheService] Generating cache (background) for range: $lowestMidi-$highestMidi');

    try {
      // Use compute to run the heavy generation in a background isolate
      final result = await compute(
        _generateCacheWorker,
        _CacheGenParams(lowestMidi, highestMidi),
      );
      
      _cache.clear();
      _cache.addAll(result);
      _cachedLowestMidi = lowestMidi;
      _cachedHighestMidi = highestMidi;
      
      debugPrint('[ExerciseCacheService] Cache generation complete: ${_cache.length} exercises cached');
    } catch (e, stackTrace) {
      debugPrint('[ExerciseCacheService] Error generating cache: $e');
      debugPrint('[ExerciseCacheService] Stack trace: $stackTrace');
    } finally {
      _isGenerating = false;
    }
    
    // Trigger background WAV generation
    // We do this after the note cache is ready so the UI is responsive first
    // (though prewarm is async/non-blocking anyway)
    final exercises = _exerciseRepo.getExercises();
    // Default to beginner difficulty for prewarming
    WavCacheManager.instance.prewarm(
      exercises: exercises,
      lowMidi: lowestMidi,
      highMidi: highestMidi,
      difficulty: PitchHighwayDifficulty.easy,
    );
  }

  /// Load cache for the current range (if range is set).
  /// Call this on app startup.
  Future<void> loadCache() async {
    final (lowestMidi, highestMidi) = await _rangeService.getRange();
    // getRange() always returns valid values (uses defaults if not set)
    await generateCache(lowestMidi: lowestMidi, highestMidi: highestMidi);
  }

  /// Clear the cache (e.g., when range is cleared or after fixing note generation bugs)
  void clearCache() {
    _cache.clear();
    _cachedLowestMidi = null;
    _cachedHighestMidi = null;
    debugPrint('[ExerciseCacheService] Cache cleared - will regenerate on next exercise load');
  }
  
  /// Force cache regeneration even if range hasn't changed
  /// Useful after fixing bugs in note generation logic (e.g., octave shift fixes)
  Future<void> forceRegenerateCache() async {
    final (lowestMidi, highestMidi) = await _rangeService.getRange();
    _cachedLowestMidi = null; // Force regeneration
    _cachedHighestMidi = null;
    await generateCache(lowestMidi: lowestMidi, highestMidi: highestMidi);
    debugPrint('[ExerciseCacheService] Cache force-regenerated for range: $lowestMidi-$highestMidi');
  }
}

/// Parameters passed to the background worker
class _CacheGenParams {
  final int lowestMidi;
  final int highestMidi;
  _CacheGenParams(this.lowestMidi, this.highestMidi);
}

/// Static worker function that runs in a separate isolate.
/// It must be a top-level function or a static method.
Map<String, Map<String?, List<ReferenceNote>>> _generateCacheWorker(_CacheGenParams params) {
  final lowestMidi = params.lowestMidi;
  final highestMidi = params.highestMidi;
  // Note: We cannot use the singleton ExerciseRepository here because singletons aren't shared across isolates.
  // We must re-instantiate it (it's lightweight) or fetch data directly.
  final exercises = ExerciseRepository().getExercises();
  final cache = <String, Map<String?, List<ReferenceNote>>>{};

  for (final exercise in exercises) {
    // Only cache exercises with highwaySpec (pitch highway exercises)
    if (exercise.highwaySpec == null || exercise.highwaySpec!.segments.isEmpty) {
      continue;
    }

    // Generate for each difficulty level
    for (final difficulty in PitchHighwayDifficulty.values) {
      // Special handling for Sirens: cache audio notes only (visual path generated separately)
      final List<ReferenceNote> notes;
      if (exercise.id == 'sirens') {
        final sirenResult = TransposedExerciseBuilder.buildSirensWithVisualPath(
          exercise: exercise,
          lowestMidi: lowestMidi,
          highestMidi: highestMidi,
          leadInSec: AudioConstants.leadInSec,
          difficulty: difficulty,
        );
        notes = sirenResult.melody; // Cache only audio notes (3 notes)
      } else {
        final sequence = TransposedExerciseBuilder.buildTransposedSequence(
          exercise: exercise,
          lowestMidi: lowestMidi,
          highestMidi: highestMidi,
          leadInSec: AudioConstants.leadInSec,
          difficulty: difficulty,
        );
        notes = sequence.melody;
      }

      final difficultyKey = difficulty?.name;
      if (!cache.containsKey(exercise.id)) {
        cache[exercise.id] = {};
      }
      cache[exercise.id]![difficultyKey] = notes;
    }

    // Also generate without difficulty (default)
    final List<ReferenceNote> notesDefault;
    if (exercise.id == 'sirens') {
      final sirenResult = TransposedExerciseBuilder.buildSirensWithVisualPath(
        exercise: exercise,
        lowestMidi: lowestMidi,
        highestMidi: highestMidi,
        leadInSec: AudioConstants.leadInSec,
        difficulty: null, // Default difficulty for cache
      );
      notesDefault = sirenResult.melody; // Cache only audio notes
    } else {
      final sequence = TransposedExerciseBuilder.buildTransposedSequence(
        exercise: exercise,
        lowestMidi: lowestMidi,
        highestMidi: highestMidi,
        leadInSec: AudioConstants.leadInSec,
        difficulty: null,
      );
      notesDefault = sequence.melody;
    }

    if (!cache.containsKey(exercise.id)) {
      cache[exercise.id] = {};
    }
    cache[exercise.id]![null] = notesDefault;
  }
  
  return cache;
}


