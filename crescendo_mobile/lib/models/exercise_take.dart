import 'dart:convert';

class ExerciseTake {
  final String id;
  final String exerciseId;
  final String title;
  final DateTime createdAt;
  final double score0to100;
  final double onPitchPct;
  final double? avgCentsAbs;
  final int stars; // 1-5

  ExerciseTake({
    required this.id,
    required this.exerciseId,
    required this.title,
    required this.createdAt,
    required this.score0to100,
    required this.onPitchPct,
    this.avgCentsAbs,
    required this.stars,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'exerciseId': exerciseId,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'score0to100': score0to100,
        'onPitchPct': onPitchPct,
        'avgCentsAbs': avgCentsAbs,
        'stars': stars,
      };

  factory ExerciseTake.fromJson(Map<String, dynamic> json) => ExerciseTake(
        id: json['id'] as String,
        exerciseId: json['exerciseId'] as String,
        title: json['title'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        score0to100: (json['score0to100'] as num).toDouble(),
        onPitchPct: (json['onPitchPct'] as num).toDouble(),
        avgCentsAbs: (json['avgCentsAbs'] as num?)?.toDouble(),
        stars: json['stars'] as int,
      );

  static List<ExerciseTake> listFromJson(String raw) {
    final data = jsonDecode(raw) as List<dynamic>;
    return data.map((e) => ExerciseTake.fromJson(e as Map<String, dynamic>)).toList();
  }

  static String listToJson(List<ExerciseTake> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());
}
