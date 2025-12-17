class ExerciseStats {
  final String exerciseId;
  final double? lastScore;
  final double? bestScore;
  final double? averageRecent;
  final double trendSlope;
  final int attemptsCount;
  final List<double> recentScores;

  const ExerciseStats({
    required this.exerciseId,
    required this.lastScore,
    required this.bestScore,
    required this.averageRecent,
    required this.trendSlope,
    required this.attemptsCount,
    required this.recentScores,
  });
}

class CategoryStats {
  final String categoryId;
  final double? score;
  final double trendSlope;
  final List<double> trendScores;
  final int attemptedExercises;

  const CategoryStats({
    required this.categoryId,
    required this.score,
    required this.trendSlope,
    required this.trendScores,
    required this.attemptedExercises,
  });
}

class OverallStats {
  final double? score;
  final double? average;
  final double? best;
  final double trendSlope;
  final List<double> trendScores;
  final int totalAttempts;

  const OverallStats({
    required this.score,
    required this.average,
    required this.best,
    required this.trendSlope,
    required this.trendScores,
    required this.totalAttempts,
  });
}

class ProgressSnapshot<T> {
  final List<T> attempts;
  final Map<String, ExerciseStats> exerciseStats;
  final Map<String, CategoryStats> categoryStats;
  final OverallStats overallStats;

  const ProgressSnapshot({
    required this.attempts,
    required this.exerciseStats,
    required this.categoryStats,
    required this.overallStats,
  });
}
