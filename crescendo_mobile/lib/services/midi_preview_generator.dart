import '../models/pitch_segment.dart';
import '../models/reference_note.dart';
import '../models/vocal_exercise.dart';

/// Generates MIDI preview notes for non-glide exercises
/// Creates a single iteration of the exercise pattern starting at C4 (MIDI 60)
class MidiPreviewGenerator {
  /// Generate preview notes for an exercise
  /// Returns a list of ReferenceNote objects representing a single iteration
  /// of the exercise pattern, transposed to start at C4 (MIDI 60)
  static List<ReferenceNote> generatePreview(VocalExercise exercise) {
    final spec = exercise.highwaySpec;
    if (spec == null || spec.segments.isEmpty) return const [];

    // Use the segments as-is (no tempo scaling for preview)
    final segments = spec.segments;
    
    // Sort segments by startMs to ensure chronological order
    final sortedSegments = List<PitchSegment>.from(segments)
      ..sort((a, b) => a.startMs.compareTo(b.startMs));

    // Find the first chronological segment's MIDI note
    final firstSegment = sortedSegments.first;
    final firstSegmentMidi = firstSegment.midiNote;
    
    // Calculate transposition to move first note to C4 (MIDI 60)
    final transposeSemitones = 60 - firstSegmentMidi;

    // Generate preview notes (single iteration, no transposition across range)
    final previewNotes = <ReferenceNote>[];
    for (final seg in sortedSegments) {
      // Skip glide segments - these should use WAV previews
      if (seg.isGlide) {
        continue;
      }

      final startSec = seg.startMs / 1000.0;
      final endSec = seg.endMs / 1000.0;
      final midi = seg.midiNote + transposeSemitones;

      previewNotes.add(ReferenceNote(
        startSec: startSec,
        endSec: endSec,
        midi: midi,
        lyric: seg.label,
      ));
    }

    return previewNotes;
  }
}
