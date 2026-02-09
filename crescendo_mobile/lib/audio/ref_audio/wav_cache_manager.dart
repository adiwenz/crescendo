import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/exercise_plan.dart';
import '../../models/pitch_highway_difficulty.dart';
import '../../models/vocal_exercise.dart';
import '../../services/exercise_plan_builder.dart';
import '../../utils/audio_constants.dart';
import 'ref_spec.dart';
import 'wav_cache_manifest.dart';
import 'wav_generation_worker.dart';

class WavJob {
  final RefSpec spec;
  final VocalExercise exercise;
  final Completer<ExercisePlan> completer;

  WavJob(this.spec, this.exercise) : completer = Completer();
}

/// Singleton manager for background WAV generation and caching.
class WavCacheManager {
  static final WavCacheManager instance = WavCacheManager._();
  WavCacheManager._();

  final WavCacheManifest _manifest = WavCacheManifest();
  final Queue<WavJob> _jobQueue = Queue();
  final Set<String> _inflightKeys = {}; // cacheKey -> job in progress
  
  // Concurrency control
  int _activeWorkers = 0;
  static const int _maxConcurrentWorkers = 2; // Keep low to avoid stutter
  
  // Memory cache for inflight futures to dedupe
  final Map<String, Future<ExercisePlan>> _pendingFutures = {};

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await _manifest.init();
    
    // Cleanup stale temp files on startup? 
    // For now, reliance on system temp cleaning is okay, 
    // or we can implement explicit cleanup later.
    
    _initialized = true;
    debugPrint('[WavCacheManager] Initialized. Manifest has ${_manifest.cacheDir.path}');
  }

  /// Returns the exercise plan with valid WAV path.
  /// If cached, returns immediately.
  /// If not, schedules generation and waits (high priority).
  Future<ExercisePlan> get(RefSpec spec, {required VocalExercise exercise}) async {
    await init();

    // 1. Check Cache Hit
    final entry = _manifest.get(spec);
    if (entry != null) {
      final file = File(entry.path);
      if (await file.exists()) {
        // Touch LRU
        _manifest.touch(spec); // fire and forget
        return _reconstructPlanFromCache(spec, exercise, entry.path);
      } else {
        // Cache inconsistency (file missing)
        await _manifest.remove(spec.cacheKey);
      }
    }

    // 2. Check In-Flight
    if (_pendingFutures.containsKey(spec.cacheKey)) {
      return _pendingFutures[spec.cacheKey]!;
    }

    // 3. Schedule High Priority Job
    final job = WavJob(spec, exercise);
    _jobQueue.addFirst(job); // Add to FRONT
    _pendingFutures[spec.cacheKey] = job.completer.future;
    
    _processQueue();
    
    return job.completer.future;
  }

  /// Queues generation for a list of exercises (low priority).
  /// Doesn't wait for result.
  void prewarm({
    required List<VocalExercise> exercises,
    required int lowMidi,
    required int highMidi,
    PitchHighwayDifficulty difficulty = PitchHighwayDifficulty.easy,
  }) async {
    await init();

    int queuedCount = 0;
    
    for (final ex in exercises) {
      final spec = RefSpec(
        exerciseId: ex.id,
        lowMidi: lowMidi,
        highMidi: highMidi,
        extraOptions: {'difficulty': difficulty.name}, // Ensure difficulty is passed
        renderVersion: 'v2', // Match system version
      );

      // Skip if cached
      if (_manifest.get(spec) != null) continue;
      
      // Skip if already pending
      if (_pendingFutures.containsKey(spec.cacheKey)) continue;

      // Add to queue (Back)
      final job = WavJob(spec, ex);
      _jobQueue.add(job);
      _pendingFutures[spec.cacheKey] = job.completer.future;
      queuedCount++;
    }

    if (queuedCount > 0) {
      debugPrint('[WavCacheManager] Prewarming $queuedCount exercises for range $lowMidi-$highMidi');
      _processQueue();
    }
  }

  Future<void> _processQueue() async {
    if (_activeWorkers >= _maxConcurrentWorkers) return;
    if (_jobQueue.isEmpty) return;

    final job = _jobQueue.removeFirst();
    _activeWorkers++;
    _inflightKeys.add(job.spec.cacheKey);

    try {
      // 1. Prepare Paths
      final tempDir = await getTemporaryDirectory();
      final tempPath = p.join(tempDir.path, '${job.spec.filename}.tmp');
      final finalPath = p.join(_manifest.cacheDir.path, job.spec.filename);
      
      // 2. Run Worker
      final result = await compute(
        WavGenerationWorker.generate,
        WavGenerationInput(
          spec: job.spec,
          exercise: job.exercise,
          tempOutputPath: tempPath,
        ),
      );

      if (result.success) {
        // 3. Move File to Cache
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
           await tempFile.rename(finalPath);
        }

        // 4. Update Manifest
        await _manifest.put(job.spec, File(finalPath));
        
        // 5. Complete Future
        // The worker returns a plan with correct duration/notes, but the path was temp.
        // We update the path to the final cached path.
        final finalPlan = result.plan.copyWith(wavFilePath: finalPath);
        job.completer.complete(finalPlan);
      } else {
        job.completer.completeError('Generation failed: ${result.errorMessage}');
      }
    } catch (e, stack) {
      debugPrint('[WavCacheManager] Worker error: $e');
      job.completer.completeError(e, stack);
    } finally {
      _activeWorkers--;
      _inflightKeys.remove(job.spec.cacheKey);
      _pendingFutures.remove(job.spec.cacheKey);
      
      // Continue processing
      _processQueue();
    }
  }

  /// Fast reconstruction of ExercisePlan from cache hit.
  Future<ExercisePlan> _reconstructPlanFromCache(
    RefSpec spec, 
    VocalExercise exercise, 
    String filePath
  ) async {
    // 1. Build basic metadata (fast)
    final difficultyName = spec.extraOptions['difficulty'] as String? ?? 'beginner';
    final difficulty = PitchHighwayDifficulty.values.firstWhere(
        (d) => d.name == difficultyName, orElse: () => PitchHighwayDifficulty.easy);

    // Note: ExercisePlanBuilder doesn't shift notes for audio offset.
    final internalPlan = await ExercisePlanBuilder.buildMetadata(
      exercise: exercise,
      lowestMidi: spec.lowMidi,
      highestMidi: spec.highMidi,
      difficulty: difficulty,
      wavFilePath: filePath,
    );

    // 2. Apply Audio Offset Shift (Same as Worker)
    final offset = AudioConstants.totalChirpOffsetSec;
    final shiftedNotes = internalPlan.notes.map((n) {
      return n.copyWith(
        startSec: n.startSec + offset,
        endSec: n.endSec + offset,
      );
    }).toList();
    
    return internalPlan.copyWith(
      notes: shiftedNotes,
      durationSec: internalPlan.durationSec + offset,
    );
  }

  /// Clear all cache.
  Future<void> clearAll() async {
    // Implement if needed for debug
    // _manifest.entries.keys.forEach(_manifest.remove);
  }
}
