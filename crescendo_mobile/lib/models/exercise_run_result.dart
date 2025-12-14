import 'exercise_note_result.dart';

class ExerciseRunResult {
  final String exerciseId;
  final DateTime startedAt;
  final int offsetMsUsed;
  final double overallScore0to100;
  final int stars;
  final List<ExerciseNoteResult> noteResults;
  final double avgAbsCents;

  ExerciseRunResult({
    required this.exerciseId,
    required this.startedAt,
    required this.offsetMsUsed,
    required this.overallScore0to100,
    required this.stars,
    required this.noteResults,
    required this.avgAbsCents,
  });
}
