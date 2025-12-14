import 'exercise_note.dart';

class ExercisePlan {
  final String title;
  final String keyLabel;
  final double bpm;
  final double gapSec;
  final List<ExerciseNote> notes;

  const ExercisePlan({
    required this.title,
    required this.keyLabel,
    required this.bpm,
    required this.gapSec,
    required this.notes,
  });
}
