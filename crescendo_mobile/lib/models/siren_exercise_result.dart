import 'reference_note.dart';
import 'siren_path.dart';

/// Result of building a Sirens exercise: visual path + minimal audio notes
class SirenExerciseResult {
  final SirenPath visualPath;
  final List<ReferenceNote> audioNotes; // Only 3 notes: bottom, top, bottom

  const SirenExerciseResult({
    required this.visualPath,
    required this.audioNotes,
  });

  /// Validate that audioNotes has exactly 3 notes
  bool get isValid => audioNotes.length == 3;
}
