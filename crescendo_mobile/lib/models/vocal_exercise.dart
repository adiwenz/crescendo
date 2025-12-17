import 'pitch_highway_spec.dart';

enum ExerciseType {
  pitchHighway,
  breathTimer,
  sovtTimer,
  sustainedPitchHold,
  pitchMatchListening,
  articulationRhythm,
  dynamicsRamp,
  cooldownRecovery,
}

enum ExerciseDifficulty { beginner, intermediate, advanced }

class VocalExercise {
  final String id;
  final String name;
  final String categoryId;
  final ExerciseType type;
  final String description;
  final String purpose;
  final int? durationSeconds;
  final int? reps;
  final ExerciseDifficulty difficulty;
  final List<String> tags;
  final PitchHighwaySpec? highwaySpec;
  final DateTime createdAt;
  final String iconKey;
  final int estimatedMinutes;

  VocalExercise({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.type,
    required this.description,
    required this.purpose,
    required this.difficulty,
    required this.tags,
    required this.createdAt,
    String? iconKey,
    int? estimatedMinutes,
    this.durationSeconds,
    this.reps,
    this.highwaySpec,
  })  : iconKey = iconKey ?? _defaultIconKey(type),
        estimatedMinutes = estimatedMinutes ?? _estimateMinutes(durationSeconds);

  static String _defaultIconKey(ExerciseType type) {
    return switch (type) {
      ExerciseType.pitchHighway => 'pitch',
      ExerciseType.breathTimer => 'breath',
      ExerciseType.sovtTimer => 'sovt',
      ExerciseType.sustainedPitchHold => 'hold',
      ExerciseType.pitchMatchListening => 'listen',
      ExerciseType.articulationRhythm => 'articulation',
      ExerciseType.dynamicsRamp => 'dynamics',
      ExerciseType.cooldownRecovery => 'recovery',
    };
  }

  static int _estimateMinutes(int? durationSeconds) {
    if (durationSeconds == null || durationSeconds <= 0) return 2;
    final mins = (durationSeconds / 60).round();
    return mins.clamp(1, 60);
  }
}
