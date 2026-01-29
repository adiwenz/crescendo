import 'dart:async';
import 'dart:math' as math;

import '../data/progress_repository.dart';
import '../models/exercise_attempt.dart';
import '../models/progress_stats.dart';
import '../services/progress_stats.dart';
import 'exercise_repository.dart';
import 'attempt_repository.dart';
import '../state/library_store.dart';
import 'package:flutter/foundation.dart';

class ProgressService {
  static final ProgressService _instance = ProgressService._internal();
  factory ProgressService() => _instance;
  ProgressService._internal();

  final ProgressRepository _repo = ProgressRepository();
  final ExerciseRepository _exerciseRepo = ExerciseRepository();
  final StreamController<ProgressSnapshot<ExerciseAttempt>> _controller =
      StreamController.broadcast();

  List<ExerciseAttempt> _cache = [];

  Stream<ProgressSnapshot<ExerciseAttempt>> get stream => _controller.stream;

  Future<void> refresh() async {
    _cache = await _repo.fetchAllAttempts();
    _controller.add(_buildSnapshot(_cache));
  }

  Future<void> persistAttempt({
    required ExerciseAttempt attempt,
    int? level,
    int? score,
  }) async {
    // 1. Persist to DB (Transaction)
    await _repo.persistAttempt(attempt: attempt, level: level, score: score);
    
    // 2. Update simple library store (for tick marks etc)
    libraryStore.markCompleted(
      attempt.exerciseId,
      score: score ?? attempt.overallScore.round(),
    );

    // 3. Force refresh AttemptRepository cache (for Progress screen)
    // This ensures UI rebuilt immediately with new data
    await AttemptRepository.instance.refresh();
  }

  // Deprecated methods
  Future<void> saveCompleteAttempt({
    required ExerciseAttempt attempt,
    required int level,
    required int score,
  }) async {
    return persistAttempt(attempt: attempt, level: level, score: score);
  }

  Future<void> saveAttempt(ExerciseAttempt attempt) async {
    return persistAttempt(attempt: attempt);
  }

  ProgressSnapshot<ExerciseAttempt> snapshot() => _buildSnapshot(_cache);

  ProgressSnapshot<ExerciseAttempt> _buildSnapshot(List<ExerciseAttempt> attempts) {
    final exercises = _exerciseRepo.getExercises();
    final categories = _exerciseRepo.getCategories();
    final exerciseStats = <String, ExerciseStats>{};
    for (final ex in exercises) {
      exerciseStats[ex.id] =
          computeExerciseStats(exerciseId: ex.id, attempts: attempts);
    }
    final categoryStats = <String, CategoryStats>{};
    for (final cat in categories) {
      categoryStats[cat.id] = computeCategoryStats(
        categoryId: cat.id,
        exercises: exercises,
        attempts: attempts,
      );
    }
    final overallStats = computeOverallStats(attempts: attempts);
    return ProgressSnapshot<ExerciseAttempt>(
      attempts: attempts,
      exerciseStats: exerciseStats,
      categoryStats: categoryStats,
      overallStats: overallStats,
    );
  }

  ExerciseAttempt buildAttempt({
    required String exerciseId,
    required String categoryId,
    required DateTime startedAt,
    required DateTime completedAt,
    required double overallScore,
    Map<String, double>? subScores,
    String? notes,
    String? pitchDifficulty,
    String? recordingPath,
    String? contourJson,
    String? targetNotesJson,
    String? segmentsJson,
    double? recorderStartSec,
    int? minMidi,
    int? maxMidi,
    String? referenceWavPath,
    int? referenceSampleRate,
    String? referenceWavSha1,
  }) {
    final id =
        '${completedAt.microsecondsSinceEpoch}_${math.Random().nextInt(1 << 20)}';
    return ExerciseAttempt(
      id: id,
      exerciseId: exerciseId,
      categoryId: categoryId,
      startedAt: startedAt,
      completedAt: completedAt,
      overallScore: overallScore,
      subScores: subScores ?? const {},
      recordingPath: recordingPath,
      contourJson: contourJson,
      targetNotesJson: targetNotesJson,
      segmentsJson: segmentsJson,
      notes: notes,
      pitchDifficulty: pitchDifficulty,
      recorderStartSec: recorderStartSec,
      minMidi: minMidi,
      maxMidi: maxMidi,
      referenceWavPath: referenceWavPath,
      referenceSampleRate: referenceSampleRate,
      referenceWavSha1: referenceWavSha1,
    );
  }
}
