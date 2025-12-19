import 'dart:convert';

class ExerciseLevelProgress {
  static const int minLevel = 1;
  static const int maxLevel = 3;

  final String exerciseId;
  final int highestUnlockedLevel;
  final int? lastSelectedLevel;
  final Map<int, int> bestScoreByLevel;
  final Map<int, int> lastScoreByLevel;
  final Map<int, int> attemptsByLevel;
  final DateTime updatedAt;

  const ExerciseLevelProgress({
    required this.exerciseId,
    required this.highestUnlockedLevel,
    required this.lastSelectedLevel,
    required this.bestScoreByLevel,
    required this.lastScoreByLevel,
    required this.attemptsByLevel,
    required this.updatedAt,
  });

  factory ExerciseLevelProgress.empty(String exerciseId) {
    return ExerciseLevelProgress(
      exerciseId: exerciseId,
      highestUnlockedLevel: minLevel,
      lastSelectedLevel: null,
      bestScoreByLevel: const {},
      lastScoreByLevel: const {},
      attemptsByLevel: const {},
      updatedAt: DateTime.now(),
    );
  }

  ExerciseLevelProgress copyWith({
    int? highestUnlockedLevel,
    int? lastSelectedLevel,
    Map<int, int>? bestScoreByLevel,
    Map<int, int>? lastScoreByLevel,
    Map<int, int>? attemptsByLevel,
    DateTime? updatedAt,
  }) {
    return ExerciseLevelProgress(
      exerciseId: exerciseId,
      highestUnlockedLevel: highestUnlockedLevel ?? this.highestUnlockedLevel,
      lastSelectedLevel: lastSelectedLevel ?? this.lastSelectedLevel,
      bestScoreByLevel: bestScoreByLevel ?? this.bestScoreByLevel,
      lastScoreByLevel: lastScoreByLevel ?? this.lastScoreByLevel,
      attemptsByLevel: attemptsByLevel ?? this.attemptsByLevel,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toDbMap() => {
        'exerciseId': exerciseId,
        'highestUnlockedLevel': highestUnlockedLevel,
        'lastSelectedLevel': lastSelectedLevel,
        'bestScoresJson': _encodeMap(bestScoreByLevel),
        'lastScoresJson': _encodeMap(lastScoreByLevel),
        'attemptsJson': _encodeMap(attemptsByLevel),
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory ExerciseLevelProgress.fromDbMap(Map<String, Object?> row) {
    final exerciseId = (row['exerciseId'] ?? '').toString();
    return ExerciseLevelProgress(
      exerciseId: exerciseId,
      highestUnlockedLevel: _parseLevel(row['highestUnlockedLevel']),
      lastSelectedLevel: _parseOptionalLevel(row['lastSelectedLevel']),
      bestScoreByLevel: _decodeMap(row['bestScoresJson']),
      lastScoreByLevel: _decodeMap(row['lastScoresJson']),
      attemptsByLevel: _decodeMap(row['attemptsJson']),
      updatedAt: _parseUpdatedAt(row['updatedAt']),
    );
  }

  static String? _encodeMap(Map<int, int> map) {
    if (map.isEmpty) return null;
    final converted = map.map((key, value) => MapEntry(key.toString(), value));
    return jsonEncode(converted);
  }

  static Map<int, int> _decodeMap(Object? raw) {
    if (raw == null) return {};
    try {
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((key, value) {
            final level = int.tryParse(key.toString()) ?? minLevel;
            final score = (value is num) ? value.toInt() : int.tryParse(value.toString()) ?? 0;
            return MapEntry(level, score);
          });
        }
      }
      if (raw is Map) {
        return raw.map((key, value) {
          final level = int.tryParse(key.toString()) ?? minLevel;
          final score = (value is num) ? value.toInt() : int.tryParse(value.toString()) ?? 0;
          return MapEntry(level, score);
        });
      }
    } catch (_) {}
    return {};
  }

  static int _parseLevel(Object? raw) {
    final value = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
    return (value ?? minLevel).clamp(minLevel, maxLevel);
  }

  static int? _parseOptionalLevel(Object? raw) {
    if (raw == null) return null;
    final value = raw is num ? raw.toInt() : int.tryParse(raw.toString());
    if (value == null) return null;
    return value.clamp(minLevel, maxLevel);
  }

  static DateTime _parseUpdatedAt(Object? raw) {
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    final parsed = int.tryParse(raw?.toString() ?? '');
    if (parsed != null) return DateTime.fromMillisecondsSinceEpoch(parsed);
    return DateTime.now();
  }
}
