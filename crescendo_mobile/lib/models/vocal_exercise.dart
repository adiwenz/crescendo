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

  const VocalExercise({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.type,
    required this.description,
    required this.purpose,
    required this.difficulty,
    required this.tags,
    required this.createdAt,
    this.durationSeconds,
    this.reps,
    this.highwaySpec,
  });
}
