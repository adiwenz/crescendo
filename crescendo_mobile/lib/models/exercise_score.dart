class ExerciseScore {
  final String id;
  final String exerciseId;
  final String categoryId;
  final DateTime createdAt;
  final double score;
  final int durationMs;

  const ExerciseScore({
    required this.id,
    required this.exerciseId,
    required this.categoryId,
    required this.createdAt,
    required this.score,
    required this.durationMs,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'exerciseId': exerciseId,
        'categoryId': categoryId,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'score': score,
        'durationMs': durationMs,
      };

  factory ExerciseScore.fromMap(Map<String, dynamic> m) {
    return ExerciseScore(
      id: m['id'] as String,
      exerciseId: m['exerciseId'] as String,
      categoryId: (m['categoryId'] ?? '').toString(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
      score: (m['score'] as num).toDouble(),
      durationMs: m['durationMs'] as int,
    );
  }
}
