import 'package:collection/collection.dart';

import '../data/seed_library.dart';
import '../state/library_store.dart';

class ProgressSummary {
  final int completedToday;
  final int totalCompleted;
  final double avgScore;
  final List<Activity> recent;
  final Map<String, double> categoryPercents;
  final List<double> trendScores;

  ProgressSummary({
    required this.completedToday,
    required this.totalCompleted,
    required this.avgScore,
    required this.recent,
    required this.categoryPercents,
    required this.trendScores,
  });
}

class Activity {
  final String exerciseId;
  final DateTime date;
  final int? score;

  Activity(this.exerciseId, this.date, this.score);
}

class SimpleProgressRepository {
  ProgressSummary buildSummary() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final completed = libraryStore.completedExerciseIds;
    final best = libraryStore.bestScores;
    final last = libraryStore.lastCompletedAt;

    final recent = last.entries
        .map((e) => Activity(e.key, e.value, best[e.key]))
        .sorted((a, b) => b.date.compareTo(a.date));
    final completedToday = recent.where((r) {
      final d = r.date;
      return d.year == today.year && d.month == today.month && d.day == today.day;
    }).length;
    final avgScore = best.isEmpty
        ? 0.0
        : best.values.fold<double>(0, (sum, v) => sum + v.toDouble()) / best.length;

    // Trend: last 7 scores by lastCompletedAt order
    final trendScores = recent.take(7).map((a) => (a.score ?? 0).toDouble()).toList().reversed.toList();

    // Category percent: using seed_library mapping
    final categories = seedLibraryCategories();
    final Map<String, double> percents = {};
    for (final c in categories) {
      final exes = seedExercisesFor(c.id);
      if (exes.isEmpty) {
        percents[c.id] = 0;
        continue;
      }
      final done = exes.where((e) => completed.contains(e.id)).length;
      percents[c.id] = done / exes.length;
    }

    return ProgressSummary(
      completedToday: completedToday,
      totalCompleted: completed.length,
      avgScore: avgScore,
      recent: recent,
      categoryPercents: percents,
      trendScores: trendScores,
    );
  }
}
