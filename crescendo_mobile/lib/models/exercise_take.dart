class ExerciseTake {
  final String exerciseId;
  final DateTime createdAt;
  final double score;
  final String audioPath;
  final String pitchPath;
  final double offsetMs;

  const ExerciseTake({
    required this.exerciseId,
    required this.createdAt,
    required this.score,
    required this.audioPath,
    required this.pitchPath,
    required this.offsetMs,
  });

  Map<String, dynamic> toMap() => {
        'exerciseId': exerciseId,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'score': score,
        'audioPath': audioPath,
        'pitchPath': pitchPath,
        'offsetMs': offsetMs,
      };

  factory ExerciseTake.fromMap(Map<String, dynamic> m) {
    return ExerciseTake(
      exerciseId: m['exerciseId'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
      score: (m['score'] as num).toDouble(),
      audioPath: m['audioPath'] as String,
      pitchPath: m['pitchPath'] as String,
      offsetMs: (m['offsetMs'] as num).toDouble(),
    );
  }
}
