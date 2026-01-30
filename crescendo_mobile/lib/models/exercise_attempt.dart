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
  final String? recordingPath;
  final String? contourJson;
  final String? targetNotesJson;
  final String? segmentsJson;
  final String? notes;
  final String? pitchDifficulty;
  final double? recorderStartSec;
  final int? minMidi;
  final int? maxMidi;
  final String? referenceWavPath;
  final int? referenceSampleRate;
  final String? referenceWavSha1;
  final int version;
  final String? dateKey; // YYYY-MM-DD in America/New_York timezone
  final bool countsForDailyEffort; // Whether this attempt counts for daily credit
  final double? completionPercent; // 0.0 to 1.0

  const ExerciseAttempt({
    required this.id,
    required this.exerciseId,
    required this.categoryId,
    required this.startedAt,
    required this.completedAt,
    required this.overallScore,
    this.subScores = const {},
    this.recordingPath,
    this.contourJson,
    this.targetNotesJson,
    this.segmentsJson,
    this.notes,
    this.pitchDifficulty,
    this.recorderStartSec,
    this.minMidi,
    this.maxMidi,
    this.referenceWavPath,
    this.referenceSampleRate,
    this.referenceWavSha1,
    this.version = 1,
    this.dateKey,
    this.countsForDailyEffort = false,
    this.completionPercent,
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
        'recordingPath': recordingPath,
        'contourJson': contourJson,
        'targetNotesJson': targetNotesJson,
        'segmentsJson': segmentsJson,
        'notes': notes,
        'pitchDifficulty': pitchDifficulty,
        'recorderStartSec': recorderStartSec,
        'referenceWavPath': referenceWavPath,
        'referenceSampleRate': referenceSampleRate,
        'referenceWavSha1': referenceWavSha1,
        'version': version,
        'dateKey': dateKey,
        'countsForDailyEffort': countsForDailyEffort ? 1 : 0,
        'completionPercent': completionPercent,
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
      recordingPath: map['recordingPath'] as String?,
      contourJson: map['contourJson'] as String?,
      targetNotesJson: map['targetNotesJson'] as String?,
      segmentsJson: map['segmentsJson'] as String?,
      notes: map['notes'] as String?,
      pitchDifficulty: map['pitchDifficulty'] as String?,
      recorderStartSec: (map['recorderStartSec'] as num?)?.toDouble(),
      minMidi: (map['minMidi'] as num?)?.toInt(),
      maxMidi: (map['maxMidi'] as num?)?.toInt(),
      referenceWavPath: map['referenceWavPath'] as String?,
      referenceSampleRate: (map['referenceSampleRate'] as num?)?.toInt(),
      referenceWavSha1: map['referenceWavSha1'] as String?,
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
      recordingPath: (m['recordingPath'] ?? m['recording'])?.toString(),
      contourJson: (m['contourJson'] ?? m['contour'])?.toString(),
      targetNotesJson: m['targetNotesJson']?.toString(),
      segmentsJson: m['segmentsJson']?.toString(),
      notes: parseNotes(m['notes']),
      pitchDifficulty: (m['pitchDifficulty'] ?? m['pitchDifficultyText'])?.toString(),
      recorderStartSec: (m['recorderStartSec'] as num?)?.toDouble(),
      minMidi: (m['minMidi'] as num?)?.toInt(),
      maxMidi: (m['maxMidi'] as num?)?.toInt(),
      referenceWavPath: m['referenceWavPath'] as String?,
      referenceSampleRate: (m['referenceSampleRate'] as num?)?.toInt(),
      referenceWavSha1: m['referenceWavSha1'] as String?,
      version: (m['version'] is num) ? (m['version'] as num).toInt() : 1,
      dateKey: m['dateKey']?.toString(),
      countsForDailyEffort: (m['countsForDailyEffort'] == 1 || m['countsForDailyEffort'] == true),
      completionPercent: (m['completionPercent'] as num?)?.toDouble(),
    );

    if (attempt.id.isEmpty && onWarning != null) {
      onWarning('Attempt row missing id, map=$m');
    }
    return attempt;
  }
}
