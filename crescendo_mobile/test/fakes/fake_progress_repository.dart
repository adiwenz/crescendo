import 'dart:async';
import 'package:crescendo_mobile/core/interfaces/i_progress_repository.dart';
import 'package:crescendo_mobile/models/exercise_attempt.dart';
import 'package:crescendo_mobile/models/exercise_score.dart';
import 'package:crescendo_mobile/models/exercise_take.dart';

class FakeProgressRepository implements IProgressRepository {
  final List<ExerciseAttempt> _attempts = [];
  final Map<String, ExerciseTake> _lastTakes = {};
  final Map<String, List<ExerciseScore>> _scores = {};

  // Test helpers
  void seedAttempt(ExerciseAttempt attempt) {
    _attempts.add(attempt);
    _scores.putIfAbsent(attempt.exerciseId, () => []).add(
      ExerciseScore(
        id: attempt.id,
        exerciseId: attempt.exerciseId,
        categoryId: attempt.categoryId,
        createdAt: attempt.completedAt ?? DateTime.now(),
        score: attempt.overallScore,
        durationMs: 0,
      )
    );
  }

  @override
  Future<int> countAttemptsForExercise(String exerciseId) async {
    return _attempts.where((a) => a.exerciseId == exerciseId).length;
  }

  @override
  Future<void> deleteAll() async {
    _attempts.clear();
    _lastTakes.clear();
    _scores.clear();
  }

  @override
  Future<List<ExerciseAttempt>> fetchAllAttempts() async {
    return List.from(_attempts);
  }

  @override
  Future<ExerciseAttempt?> fetchAttempt(String id) async {
    return _attempts.cast<ExerciseAttempt?>().firstWhere((a) => a?.id == id, orElse: () => null);
  }

  @override
  Future<List<ExerciseAttempt>> fetchAttemptSummaries() async {
    // For fake, summaries are just the attempts
    return List.from(_attempts);
  }
  
  @override
  Future<List<ExerciseAttempt>> fetchAttemptsForExercise(String exerciseId) async {
    return _attempts.where((a) => a.exerciseId == exerciseId).toList();
  }

  @override
  Future<ExerciseScore?> fetchLastScore(String exerciseId) async {
    final list = _scores[exerciseId];
    if (list == null || list.isEmpty) return null;
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.first;
  }

  @override
  Future<ExerciseTake?> fetchLastTake(String exerciseId) async {
    return _lastTakes[exerciseId];
  }

  @override
  Future<List<ExerciseScore>> fetchScoreHistory(String exerciseId) async {
    final list = _scores[exerciseId] ?? [];
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<void> persistAttempt({required ExerciseAttempt attempt, int? level, int? score}) async {
    _attempts.add(attempt);
    
    // Add to scores
    _scores.putIfAbsent(attempt.exerciseId, () => []).add(
      ExerciseScore(
        id: attempt.id,
        exerciseId: attempt.exerciseId,
        categoryId: attempt.categoryId,
        createdAt: attempt.completedAt ?? DateTime.now(),
        score: attempt.overallScore,
        durationMs: 0,
      )
    );

    // Update last take if applicable
    if (attempt.recordingPath != null || attempt.contourJson != null) {
      _lastTakes[attempt.exerciseId] = ExerciseTake(
        exerciseId: attempt.exerciseId,
        createdAt: attempt.completedAt ?? DateTime.now(),
        score: attempt.overallScore,
        audioPath: attempt.recordingPath,
        pitchPath: null, // Simplified for fake
        offsetMs: attempt.recorderStartSec ?? 0,
        minMidi: attempt.minMidi ?? 0,
        maxMidi: attempt.maxMidi ?? 0,
        referenceWavPath: attempt.referenceWavPath,
        referenceSampleRate: attempt.referenceSampleRate,
        referenceWavSha1: attempt.referenceWavSha1,
        pitchDifficulty: attempt.pitchDifficulty,
      );
    }
  }
}
