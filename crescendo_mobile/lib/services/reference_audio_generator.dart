import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/exercise_plan.dart';
import '../models/vocal_exercise.dart';
import '../models/pitch_highway_difficulty.dart';
import '../models/reference_note.dart';
import 'exercise_plan_builder.dart';
import 'review_audio_bounce_service.dart';
import 'vocal_range_service.dart';
import '../utils/audio_constants.dart';

/// Orchestrates background synthesis and caching of exercise reference WAV files.
class ReferenceAudioGenerator {
  static final ReferenceAudioGenerator instance = ReferenceAudioGenerator._();
  ReferenceAudioGenerator._();
  
  // Public factory for legacy code (ReferenceAudioCacheService)
  factory ReferenceAudioGenerator() => instance;

  static const int defaultSampleRate = AudioConstants.audioSampleRate;
  static const String cacheVersion = 'v6';

  final _bounceService = ReviewAudioBounceService();
  final _vocalRangeService = VocalRangeService();

  /// De-duplication map to avoid redundant background tasks.
  final Map<String, Future<ExercisePlan>> _activeRequests = {};

  /// Directory where generated reference WAVs are stored.
  Future<Directory> get _cacheDir async {
    final base = await getApplicationCacheDirectory();
    final dir = Directory(p.join(base.path, 'exercise_ref'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Prepares an [ExercisePlan] for the given exercise and difficulty.
  /// If a cached version exists, it returns it instantly.
  /// Otherwise, it performs background synthesis and caches the result.
  Future<ExercisePlan> prepare(
    VocalExercise exercise,
    PitchHighwayDifficulty difficulty,
  ) async {
    // 1. Get user range
    final (low, high) = await _vocalRangeService.getRange();

    // 2. Compute metadata to check cache
    final rangeHash = '${low}-${high}';
    final patternHash = ExercisePlanBuilder.generatePatternHash(exercise, difficulty);

    // Use centralized version constant
    final cacheKey = '${cacheVersion}_${exercise.id}_${rangeHash}_${patternHash}';
    
    // Check de-duplication map first
    if (_activeRequests.containsKey(cacheKey)) {
      debugPrint('[RefGen] Reusing in-flight request for $cacheKey');
      return _activeRequests[cacheKey]!;
    }

    // Fast-path: check cache
    final sw = Stopwatch()..start();
    final cached = await tryGetCached(exercise, difficulty);
    if (cached != null) {
      debugPrint('[RefGen] Cache HIT for $cacheKey (${sw.elapsedMilliseconds}ms)');
      return cached;
    }

    final dir = await _cacheDir;
    final wavPath = p.join(dir.path, '$cacheKey.wav');
    final metaPath = p.join(dir.path, '$cacheKey.json');

    // Trigger background generation
    final future = _generateInternal(
      cacheKey: cacheKey,
      exercise: exercise,
      difficulty: difficulty,
      low: low,
      high: high,
      wavPath: wavPath,
      metaPath: metaPath,
      rangeHash: rangeHash,
      patternHash: patternHash,
    );

    _activeRequests[cacheKey] = future;
    
    try {
      return await future;
    } finally {
      _activeRequests.remove(cacheKey);
    }
  }

  Future<ExercisePlan> _generateInternal({
    required String cacheKey,
    required VocalExercise exercise,
    required PitchHighwayDifficulty difficulty,
    required int low,
    required int high,
    required String wavPath,
    required String metaPath,
    required String rangeHash,
    required String patternHash,
  }) async {
    debugPrint('[RefGen] Cache MISS - Requesting background generation for $cacheKey...');
    final startTime = DateTime.now();

    // Move heavy work to Isolate
    final plan = await compute((_) async {
      // 1. Build metadata (transposition logic)
      final internalPlan = await ExercisePlanBuilder.buildMetadata(
        exercise: exercise,
        lowestMidi: low,
        highestMidi: high,
        difficulty: difficulty,
        wavFilePath: wavPath,
      );

      // 2. Synthesis (PCM generation and WAV writing)
      final tempWavPath = '${wavPath}.tmp';
      final bounceService = ReviewAudioBounceService();
      
      if (internalPlan.chordEvents.isNotEmpty) {
         await bounceService.renderTickBasedWav(
            melodyNotes: internalPlan.notes,
            chordEvents: internalPlan.chordEvents,
            modEvents: internalPlan.modEvents,
            initialRootMidi: internalPlan.initialRootMidi,
            durationSec: internalPlan.durationSec,
            sampleRate: AudioConstants.audioSampleRate,
            savePath: tempWavPath,
         );
      } else {
          await bounceService.renderReferenceWav(
            notes: internalPlan.notes,
            harmonyNotes: internalPlan.harmonyNotes,
            durationSec: internalPlan.durationSec,
            sampleRate: AudioConstants.audioSampleRate,
            savePath: tempWavPath,
          );
      }

      // Atomic rename
      await File(tempWavPath).rename(wavPath);

      // 3. Save sidecar metadata
      final meta = {
        'exerciseId': exercise.id,
        'rangeHash': rangeHash,
        'patternHash': patternHash,
        'durationSec': internalPlan.durationSec,
        'generatedAt': DateTime.now().toIso8601String(),
      };
      await File(metaPath).writeAsString(jsonEncode(meta));

      // SHIFT NOTES so the UI aligns with the audio (which now has chirp offset)
      final offset = AudioConstants.totalChirpOffsetSec;
      
      final shiftedNotes = internalPlan.notes.map((n) {
         return n.copyWith(
           startSec: n.startSec + offset,
           endSec: n.endSec + offset,
         );
      }).toList();

      final shiftedHarmony = internalPlan.harmonyNotes.map((n) {
         return n.copyWith(
           startSec: n.startSec + offset,
           endSec: n.endSec + offset,
         );
      }).toList();

      return internalPlan.copyWith(
         notes: shiftedNotes,
         harmonyNotes: shiftedHarmony,
         durationSec: internalPlan.durationSec + offset,
      );
    }, null);

    final elapsed = DateTime.now().difference(startTime);
    debugPrint('[RefGen] Background task for $cacheKey finished in ${elapsed.inMilliseconds}ms');

    return plan;
  }

  /// Fast-path check for cached audio. Returns null if not cached or invalid.
  Future<ExercisePlan?> tryGetCached(
    VocalExercise exercise,
    PitchHighwayDifficulty difficulty,
  ) async {
    final (low, high) = await _vocalRangeService.getRange();
    final rangeHash = '${low}-${high}';
    final patternHash = ExercisePlanBuilder.generatePatternHash(exercise, difficulty);
    final cacheKey = '${cacheVersion}_${exercise.id}_${rangeHash}_${patternHash}';

    final dir = await _cacheDir;
    final wavPath = p.join(dir.path, '$cacheKey.wav');
    final metaPath = p.join(dir.path, '$cacheKey.json');
    final wavFile = File(wavPath);
    final metaFile = File(metaPath);

    if (await wavFile.exists() && await metaFile.exists()) {
      try {
        final metaJson = await metaFile.readAsString();
        final meta = jsonDecode(metaJson);
        if (meta['rangeHash'] == rangeHash && meta['patternHash'] == patternHash) {
          final plan = await compute((_) => ExercisePlanBuilder.buildMetadata(
            exercise: exercise,
            lowestMidi: low,
            highestMidi: high,
            difficulty: difficulty,
            wavFilePath: wavPath,
          ), null);

          // Apply SHIFT for cached items too
          final offset = AudioConstants.totalChirpOffsetSec;
          final shiftedNotes = plan.notes.map((n) {
             return n.copyWith(
               startSec: n.startSec + offset,
               endSec: n.endSec + offset,
             );
          }).toList();

          final shiftedHarmony = plan.harmonyNotes.map((n) {
             return n.copyWith(
               startSec: n.startSec + offset,
               endSec: n.endSec + offset,
             );
          }).toList();

          return plan.copyWith(
             notes: shiftedNotes,
             harmonyNotes: shiftedHarmony,
             durationSec: plan.durationSec + offset,
          );
        }
      } catch (e) {
        debugPrint('[RefGen] tryGetCached validation failed: $e');
      }
    }
    return null;
  }

  /// Clears the entire reference audio cache.
  Future<void> clearCache() async {
    final dir = await _cacheDir;
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
