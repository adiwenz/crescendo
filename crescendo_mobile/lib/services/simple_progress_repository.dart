import 'package:collection/collection.dart';

import '../models/exercise_attempt.dart';
import '../models/exercise_category.dart';
import '../models/vocal_exercise.dart';
import '../services/exercise_repository.dart';
import 'attempt_repository.dart';

class ProgressSummary {
  final int completedToday;
  final int totalCompleted;
  final double avgScore;
  final List<Activity> recent;
  final List<CategoryProgressSummary> categories;
  final List<double> trendScores;

  ProgressSummary({
    required this.completedToday,
    required this.totalCompleted,
    required this.avgScore,
    required this.recent,
    required this.categories,
    required this.trendScores,
  });
}

class Activity {
  final String exerciseId;
  final String exerciseTitle;
  final String categoryId;
  final String categoryTitle;
  final DateTime date;
  final int? score;

  Activity({
    required this.exerciseId,
    required this.exerciseTitle,
    required this.categoryId,
    required this.categoryTitle,
    required this.date,
    required this.score,
  });
}

class CategoryProgressSummary {
  final String categoryId;
  final String title;
  final int completedCount;
  final int totalCount;
  double get percent => totalCount == 0 ? 0 : completedCount / totalCount;

  CategoryProgressSummary({
    required this.categoryId,
    required this.title,
    required this.completedCount,
    required this.totalCount,
  });
}

class SimpleProgressRepository {
  Future<ProgressSummary> buildSummary() async {
    try {
      await AttemptRepository.instance.ensureLoaded();
      // After ensureLoaded(), the cache is already populated (even if empty)
      // No need to call refresh() again - that would trigger listeners and cause loops
      final attempts = AttemptRepository.instance.cache;
      return _buildSummaryFrom(attempts);
    } catch (_) {
      // As a fallback, return empty summary.
      return ProgressSummary(
        completedToday: 0,
        totalCompleted: 0,
        avgScore: 0,
        recent: const [],
        categories: _emptyCategories(),
        trendScores: const [],
      );
    }
  }

  ProgressSummary buildSummaryFromCache() {
    return _buildSummaryFrom(AttemptRepository.instance.cache);
  }

  ProgressSummary _buildSummaryFrom(List<ExerciseAttempt> attempts) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final repo = ExerciseRepository();
    final categories = repo.getCategories();
    final allExercises = <String, VocalExercise>{};
    for (final ex in repo.getExercises()) {
      allExercises[ex.id] = ex;
    }

    if (attempts.isEmpty) {
      return ProgressSummary(
        completedToday: 0,
        totalCompleted: 0,
        avgScore: 0,
        recent: const [],
        categories: _emptyCategories(),
        trendScores: const [],
      );
    }

    // latest per exercise
    final latestByExercise = <String, ExerciseAttempt>{};
    for (final a in attempts.sorted((a, b) {
      final aTime = a.completedAt?.millisecondsSinceEpoch ?? 0;
      final bTime = b.completedAt?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    })) {
      latestByExercise.putIfAbsent(a.exerciseId, () => a);
    }

    final recent = attempts
        .where((a) => allExercises.containsKey(a.exerciseId))
        .sorted((a, b) {
          final aTime = a.completedAt?.millisecondsSinceEpoch ?? 0;
          final bTime = b.completedAt?.millisecondsSinceEpoch ?? 0;
          return bTime.compareTo(aTime);
        })
        .map((a) {
          final ex = allExercises[a.exerciseId];
          ExerciseCategory? cat;
          if (ex != null && categories.isNotEmpty) {
            try {
              cat = categories.firstWhere((c) => c.id == ex.categoryId);
            } catch (_) {
              cat = categories.first;
            }
          }
          return Activity(
            exerciseId: ex?.id ?? a.exerciseId,
            exerciseTitle: ex?.name ?? 'Unknown exercise',
            categoryId: cat?.id ?? (ex?.categoryId ?? 'unknown'),
            categoryTitle: cat?.title ?? 'Unknown',
            date: a.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            score: a.overallScore.round(),
          );
        })
        .toList();

    final completedToday = recent.where((r) {
      final d = r.date;
      return d.year == today.year && d.month == today.month && d.day == today.day;
    }).length;

    final avgScore = latestByExercise.isEmpty
        ? 0.0
        : latestByExercise.values
                .map((a) => a.overallScore)
                .fold<double>(0, (sum, v) => sum + v) /
            latestByExercise.length;

    final trendScores = recent.take(7).map((a) => (a.score ?? 0).toDouble()).toList().reversed.toList();

    final List<CategoryProgressSummary> categorySummaries = categories.map((c) {
      final exes = repo.getExercisesForCategory(c.id);
      final completedCount =
          exes.where((e) => latestByExercise.containsKey(e.id)).length;
      return CategoryProgressSummary(
        categoryId: c.id,
        title: c.title,
        completedCount: completedCount,
        totalCount: exes.length,
      );
    }).toList();

    return ProgressSummary(
      completedToday: completedToday,
      totalCompleted: attempts.length,
      avgScore: avgScore,
      recent: recent,
      categories: categorySummaries,
      trendScores: trendScores,
    );
  }

  List<CategoryProgressSummary> _emptyCategories() {
    final repo = ExerciseRepository();
    return repo.getCategories()
        .map((c) {
          final exes = repo.getExercisesForCategory(c.id);
          return CategoryProgressSummary(
            categoryId: c.id,
            title: c.title,
            completedCount: 0,
            totalCount: exes.length,
          );
        })
        .toList();
  }
}
