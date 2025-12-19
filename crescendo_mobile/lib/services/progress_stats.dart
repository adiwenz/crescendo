import 'dart:math' as math;

import '../models/exercise_attempt.dart';
import '../models/progress_stats.dart';
import '../models/vocal_exercise.dart';

ExerciseStats computeExerciseStats({
  required String exerciseId,
  required List<ExerciseAttempt> attempts,
  int recentCount = 5,
  int trendCount = 8,
}) {
  final list = attempts.where((a) => a.exerciseId == exerciseId).toList()
    ..sort((a, b) {
      final aTime = a.completedAt?.millisecondsSinceEpoch ?? 0;
      final bTime = b.completedAt?.millisecondsSinceEpoch ?? 0;
      return aTime.compareTo(bTime);
    });
  if (list.isEmpty) {
    return ExerciseStats(
      exerciseId: exerciseId,
      lastScore: null,
      bestScore: null,
      averageRecent: null,
      trendSlope: 0,
      attemptsCount: 0,
      recentScores: const [],
    );
  }
  final scores = list.map((a) => a.overallScore).toList();
  final last = scores.last;
  final best = scores.reduce(math.max);
  final recent = scores.sublist(math.max(0, scores.length - recentCount));
  final avgRecent = recent.reduce((a, b) => a + b) / recent.length;
  final trend = _trendSlope(scores, trendCount);
  final recentTrend = scores.sublist(math.max(0, scores.length - trendCount));
  return ExerciseStats(
    exerciseId: exerciseId,
    lastScore: last,
    bestScore: best,
    averageRecent: avgRecent,
    trendSlope: trend,
    attemptsCount: scores.length,
    recentScores: recentTrend,
  );
}

CategoryStats computeCategoryStats({
  required String categoryId,
  required List<VocalExercise> exercises,
  required List<ExerciseAttempt> attempts,
  int perExerciseRecentCount = 5,
  int trendCount = 8,
}) {
  final exerciseIds =
      exercises.where((e) => e.categoryId == categoryId).map((e) => e.id).toList();
  final scoresByExercise = <double>[];
  for (final exId in exerciseIds) {
    final exAttempts = attempts.where((a) => a.exerciseId == exId).toList()
      ..sort((a, b) {
        final aTime = a.completedAt?.millisecondsSinceEpoch ?? 0;
        final bTime = b.completedAt?.millisecondsSinceEpoch ?? 0;
        return aTime.compareTo(bTime);
      });
    if (exAttempts.isEmpty) continue;
    final exScores = exAttempts.map((a) => a.overallScore).toList();
    final recent = exScores.sublist(math.max(0, exScores.length - perExerciseRecentCount));
    final avgRecent = recent.reduce((a, b) => a + b) / recent.length;
    scoresByExercise.add(avgRecent);
  }
  final categoryScore = scoresByExercise.isEmpty
      ? null
      : scoresByExercise.reduce((a, b) => a + b) / scoresByExercise.length;

  final categoryAttempts =
      attempts.where((a) => a.categoryId == categoryId).toList()
        ..sort((a, b) {
          final aTime = a.completedAt?.millisecondsSinceEpoch ?? 0;
          final bTime = b.completedAt?.millisecondsSinceEpoch ?? 0;
          return aTime.compareTo(bTime);
        });
  final categoryScores = categoryAttempts.map((a) => a.overallScore).toList();
  final recentTrend = categoryScores.sublist(math.max(0, categoryScores.length - trendCount));

  return CategoryStats(
    categoryId: categoryId,
    score: categoryScore,
    trendSlope: _trendSlope(categoryScores, trendCount),
    trendScores: recentTrend,
    attemptedExercises: scoresByExercise.length,
  );
}

OverallStats computeOverallStats({
  required List<ExerciseAttempt> attempts,
  int recentCount = 10,
  int trendCount = 30,
}) {
  if (attempts.isEmpty) {
    return const OverallStats(
      score: null,
      average: null,
      best: null,
      trendSlope: 0,
      trendScores: [],
      totalAttempts: 0,
    );
  }
  final sorted = List<ExerciseAttempt>.from(attempts)
    ..sort((a, b) {
      final aTime = a.completedAt?.millisecondsSinceEpoch ?? 0;
      final bTime = b.completedAt?.millisecondsSinceEpoch ?? 0;
      return aTime.compareTo(bTime);
    });
  final scores = sorted.map((a) => a.overallScore).toList();
  final recent = scores.sublist(math.max(0, scores.length - recentCount));
  final weighted = _weightedAverage(recent);
  final avg = scores.reduce((a, b) => a + b) / scores.length;
  final best = scores.reduce(math.max);
  final trendScores = scores.sublist(math.max(0, scores.length - trendCount));
  return OverallStats(
    score: weighted,
    average: avg,
    best: best,
    trendSlope: _trendSlope(scores, trendCount),
    trendScores: trendScores,
    totalAttempts: scores.length,
  );
}

List<ExerciseAttempt> filterAttemptsByWindow(
  List<ExerciseAttempt> attempts, {
  required DateTime now,
  required Duration? window,
}) {
  if (window == null) return attempts;
  final cutoff = now.subtract(window);
  return attempts.where((a) => (a.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0)).isAfter(cutoff)).toList();
}

double _weightedAverage(List<double> values) {
  if (values.isEmpty) return 0;
  double weightedSum = 0;
  double weightTotal = 0;
  for (var i = 0; i < values.length; i++) {
    final weight = i + 1;
    weightedSum += values[i] * weight;
    weightTotal += weight;
  }
  return weightedSum / weightTotal;
}

double _trendSlope(List<double> values, int maxCount) {
  if (values.length < 2) return 0;
  final recent = values.sublist(math.max(0, values.length - maxCount));
  if (recent.length < 2) return 0;
  final n = recent.length;
  final meanX = (n - 1) / 2;
  final meanY = recent.reduce((a, b) => a + b) / n;
  double num = 0;
  double den = 0;
  for (var i = 0; i < n; i++) {
    final dx = i - meanX;
    num += dx * (recent[i] - meanY);
    den += dx * dx;
  }
  if (den == 0) return 0;
  return num / den;
}
