import 'dart:convert';

class ExerciseAttempt {
  final String id;
  final String exerciseId;
  final String categoryId;
  final DateTime startedAt;
  final DateTime completedAt;
  final double overallScore;
  final Map<String, double>? subScores;
  final String? notes;
  final String? pitchDifficulty;
  final int version;

  const ExerciseAttempt({
    required this.id,
    required this.exerciseId,
    required this.categoryId,
    required this.startedAt,
    required this.completedAt,
    required this.overallScore,
    this.subScores,
    this.notes,
    this.pitchDifficulty,
    this.version = 1,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'exerciseId': exerciseId,
        'categoryId': categoryId,
        'startedAt': startedAt.toIso8601String(),
        'completedAt': completedAt.toIso8601String(),
        'overallScore': overallScore,
        'subScoresJson': subScores == null ? null : jsonEncode(subScores),
        'notes': notes,
        'pitchDifficulty': pitchDifficulty,
        'version': version,
      };

  factory ExerciseAttempt.fromMap(Map<String, dynamic> map) {
    final rawScores = map['subScoresJson'] as String?;
    Map<String, double>? scores;
    if (rawScores != null && rawScores.isNotEmpty) {
      final decoded = jsonDecode(rawScores) as Map<String, dynamic>;
      scores = decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    }
    return ExerciseAttempt(
      id: map['id'] as String,
      exerciseId: map['exerciseId'] as String,
      categoryId: map['categoryId'] as String,
      startedAt: DateTime.parse(map['startedAt'] as String),
      completedAt: DateTime.parse(map['completedAt'] as String),
      overallScore: (map['overallScore'] as num).toDouble(),
      subScores: scores,
      notes: map['notes'] as String?,
      pitchDifficulty: map['pitchDifficulty'] as String?,
      version: (map['version'] as num?)?.toInt() ?? 1,
    );
  }
}
