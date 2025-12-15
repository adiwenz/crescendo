import 'dart:convert';

class HoldExerciseResult {
  final DateTime timestamp;
  final double targetHz;
  final double toleranceCents;
  final bool success;
  final double timeToSuccessSec;
  final double avgCentsError;
  final double avgRms;

  HoldExerciseResult({
    required this.timestamp,
    required this.targetHz,
    required this.toleranceCents,
    required this.success,
    required this.timeToSuccessSec,
    required this.avgCentsError,
    required this.avgRms,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'targetHz': targetHz,
        'toleranceCents': toleranceCents,
        'success': success,
        'timeToSuccessSec': timeToSuccessSec,
        'avgCentsError': avgCentsError,
        'avgRms': avgRms,
      };

  factory HoldExerciseResult.fromJson(Map<String, dynamic> json) {
    return HoldExerciseResult(
      timestamp: DateTime.parse(json['timestamp'] as String),
      targetHz: (json['targetHz'] as num).toDouble(),
      toleranceCents: (json['toleranceCents'] as num).toDouble(),
      success: json['success'] as bool? ?? false,
      timeToSuccessSec: (json['timeToSuccessSec'] as num).toDouble(),
      avgCentsError: (json['avgCentsError'] as num).toDouble(),
      avgRms: (json['avgRms'] as num).toDouble(),
    );
  }

  static List<HoldExerciseResult> listFromJson(String raw) {
    final data = jsonDecode(raw) as List<dynamic>;
    return data
        .map((e) => HoldExerciseResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String listToJson(List<HoldExerciseResult> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());
}
