import 'pitch_highway_difficulty.dart';
import 'vocal_exercise.dart';

class ExerciseInstance {
  final String baseExerciseId;
  final int transposeSemitones;
  final int minNote;
  final int maxNote;
  final String label;
  final PitchHighwayDifficulty difficulty;

  ExerciseInstance({
    required this.baseExerciseId,
    required this.transposeSemitones,
    required this.minNote,
    required this.maxNote,
    required this.label,
    this.difficulty = PitchHighwayDifficulty.medium,
  });

  VocalExercise apply(VocalExercise base) {
    return base.transpose(transposeSemitones);
  }
}
