class ExerciseNoteResult {
  final int noteIndex;
  final int targetMidi;
  final double pctOnPitch;
  final double avgCents;
  final double avgAbsCents;
  final double medianAbsCents;
  final double maxAbsCents;

  ExerciseNoteResult({
    required this.noteIndex,
    required this.targetMidi,
    required this.pctOnPitch,
    required this.avgCents,
    required this.avgAbsCents,
    required this.medianAbsCents,
    required this.maxAbsCents,
  });
}
