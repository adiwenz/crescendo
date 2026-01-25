import 'dart:async';
import 'dart:io';
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

  final _bounceService = ReviewAudioBounceService();
  final _vocalRangeService = VocalRangeService();

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
    final patternHash = '${exercise.id}_${difficulty.name}';
    // Adding version prefix to invalidate old glide-based caches
    const version = 'v2';
    final cacheKey = '${version}_${exercise.id}_${rangeHash}_${patternHash}';
    
    final dir = await _cacheDir;
    final wavPath = p.join(dir.path, '$cacheKey.wav');
    final wavFile = File(wavPath);

    // Cache HIT - REMOVED per user request to always generate on the fly
    // if (await wavFile.exists()) { ... }

    // Always Perform on-the-fly synthesis
    debugPrint('[RefGen] Generating reference on the fly for $cacheKey...');
    
    final startTime = DateTime.now();
    
    // Build metadata
    final plan = await ExercisePlanBuilder.buildMetadata(
      exercise: exercise,
      lowestMidi: low,
      highestMidi: high,
      difficulty: difficulty,
      wavFilePath: wavPath,
    );

    // Synthesize WAV in background
    // Note: ReviewAudioBounceService is already highly optimized with Sine Lookup Tables.
    // Calling it here will generate the file at 48kHz.
    await _bounceService.renderReferenceWav(
      notes: plan.notes,
      durationSec: plan.durationSec,
      sampleRate: AudioConstants.audioSampleRate,
      soundFontAssetPath: 'assets/soundfonts/default.sf2',
      program: 0,
      savePath: wavPath, // Target path
    );

    final elapsed = DateTime.now().difference(startTime);
    debugPrint('[RefGen] Synthesized $cacheKey in ${elapsed.inMilliseconds}ms');

    return plan;
  }

  /// Shim for legacy code (ReferenceAudioCacheService)
  Future<ReferenceAudioResult> generateAudio({
    required List<ReferenceNote> notes,
    required int sampleRate,
    required String outputPath,
  }) async {
    final lastNoteEnd = notes.isEmpty ? 0.0 : notes.map((n) => n.endSec).reduce((a, b) => a > b ? a : b);
    final durationSec = lastNoteEnd + 1.0;

    final file = await _bounceService.renderReferenceWav(
      notes: notes,
      durationSec: durationSec,
      sampleRate: sampleRate,
      soundFontAssetPath: 'assets/soundfonts/default.sf2',
      program: 0,
      savePath: outputPath,
    );

    return ReferenceAudioResult(
      file: file,
      durationMs: (durationSec * 1000).round(),
    );
  }

  /// Clears the entire reference audio cache.
  Future<void> clearCache() async {
    final dir = await _cacheDir;
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}

/// Shim result for legacy code
class ReferenceAudioResult {
  final File file;
  final int durationMs;
  ReferenceAudioResult({required this.file, required this.durationMs});
}
