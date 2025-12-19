import 'dart:convert';

import 'package:flutter/foundation.dart';

class ExerciseAttempt {
  final String id;
  final String exerciseId;
  final String categoryId;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final double overallScore;
  final Map<String, double> subScores;
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
    this.subScores = const {},
    this.notes,
    this.pitchDifficulty,
    this.version = 1,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'exerciseId': exerciseId,
        'categoryId': categoryId,
        // Store millis for schema consistency
        'startedAt': startedAt?.millisecondsSinceEpoch,
        'completedAt': completedAt?.millisecondsSinceEpoch,
        'overallScore': overallScore,
        'subScoresJson': subScores.isEmpty ? null : jsonEncode(subScores),
        'notes': notes,
        'pitchDifficulty': pitchDifficulty,
        'version': version,
      };

  /// Legacy simple parser (kept for compatibility).
  factory ExerciseAttempt.fromMap(Map<String, dynamic> map) {
    return ExerciseAttempt(
      id: map['id'] as String,
      exerciseId: map['exerciseId'] as String,
      categoryId: map['categoryId'] as String,
      startedAt: DateTime.tryParse(map['startedAt'] as String),
      completedAt: DateTime.tryParse(map['completedAt'] as String),
      overallScore: (map['overallScore'] as num?)?.toDouble() ?? 0,
      subScores: const {},
      notes: map['notes'] as String?,
      pitchDifficulty: map['pitchDifficulty'] as String?,
      version: (map['version'] as num?)?.toInt() ?? 1,
    );
  }

  /// Defensive parser for DB rows with mixed/legacy types.
  factory ExerciseAttempt.fromDbMap(
    Map<String, Object?> m, {
    void Function(String msg)? onWarning,
  }) {
    DateTime? parseDate(dynamic v) {
      try {
        if (v == null) return null;
        if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
        if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
        if (v is String && v.isNotEmpty) {
          final asInt = int.tryParse(v);
          if (asInt != null) return DateTime.fromMillisecondsSinceEpoch(asInt);
          return DateTime.tryParse(v);
        }
      } catch (_) {}
      return null;
    }

    double parseScore(dynamic v) {
      try {
        if (v == null) return 0;
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v) ?? 0;
      } catch (_) {}
      return 0;
    }

    Map<String, double> parseScores(dynamic v) {
      try {
        if (v == null) return {};
        if (v is Map) {
          return v.map((key, value) =>
              MapEntry(key.toString(), (value as num?)?.toDouble() ?? 0));
        }
        if (v is String && v.isNotEmpty) {
          final decoded = jsonDecode(v);
          if (decoded is Map) {
            return decoded.map((key, value) =>
                MapEntry(key.toString(), (value as num?)?.toDouble() ?? 0));
          }
        }
      } catch (e) {
        onWarning?.call('subScores parse failed for id=${m['id']}: $e');
      }
      return {};
    }

    String? parseNotes(dynamic v) {
      try {
        if (v == null) return null;
        if (v is String) return v;
        if (v is Map || v is List) return jsonEncode(v);
      } catch (_) {}
      return null;
    }

    final attempt = ExerciseAttempt(
      id: (m['id'] ?? '').toString(),
      exerciseId: (m['exerciseId'] ?? '').toString(),
      categoryId: (m['categoryId'] ?? '').toString(),
      startedAt: parseDate(m['startedAt']),
      completedAt: parseDate(m['completedAt']),
      overallScore: parseScore(m['overallScore']),
      subScores: parseScores(m['subScores'] ?? m['subScoresJson']),
      notes: parseNotes(m['notes']),
      pitchDifficulty: (m['pitchDifficulty'] ?? m['pitchDifficultyText'])?.toString(),
      version: (m['version'] is num) ? (m['version'] as num).toInt() : 1,
    );

    if (attempt.id.isEmpty && onWarning != null) {
      onWarning('Attempt row missing id, map=$m');
    }
    return attempt;
  }
}
