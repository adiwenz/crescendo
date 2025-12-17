class ExerciseNoteSegment {
  final int midi;
  final double startSec;
  final double durationSec;
  final String? syllable;

  const ExerciseNoteSegment({
    required this.midi,
    required this.startSec,
    required this.durationSec,
    this.syllable,
  });
}
