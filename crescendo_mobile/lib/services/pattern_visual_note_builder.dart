import 'package:flutter/foundation.dart';
import '../models/pattern_spec.dart';
import '../models/reference_note.dart';

/// Builds visual notes from pattern specifications for the full exercise run.
class PatternVisualNoteBuilder {
  /// Build visual notes from a pattern spec, expanding it across the user's vocal range.
  /// 
  /// Returns a list of ReferenceNote objects with absolute times and MIDI values,
  /// ready for use by the pitch highway painter.
  static List<ReferenceNote> buildVisualNotesFromPattern({
    required PatternSpec pattern,
    required int lowestMidi,
    required int highestMidi,
    double leadInSec = 2.0,
  }) {
    final visualNotes = <ReferenceNote>[];

    // Calculate pattern transposition range
    final maxDeltaInPattern = pattern.maxMidiDelta;
    
    // The last pattern's base MIDI must satisfy:
    // baseMidiLast + maxDeltaInPattern == highestMidi
    // So: baseMidiLast = highestMidi - maxDeltaInPattern
    final baseMidiLast = highestMidi - maxDeltaInPattern;
    
    if (baseMidiLast < lowestMidi) {
      debugPrint('[PatternVisualNoteBuilder] WARNING: Range too small. lowestMidi=$lowestMidi, highestMidi=$highestMidi, maxDelta=$maxDeltaInPattern, baseMidiLast=$baseMidiLast');
      return [];
    }

    // Calculate number of patterns
    final patternCount = (baseMidiLast - lowestMidi) + 1;
    
    debugPrint('[PatternVisualNoteBuilder] Building visual notes:');
    debugPrint('  lowestMidi=$lowestMidi, highestMidi=$highestMidi');
    debugPrint('  maxDeltaInPattern=$maxDeltaInPattern');
    debugPrint('  baseMidiLast=$baseMidiLast');
    debugPrint('  patternCount=$patternCount');
    debugPrint('  patternDurationSec=${pattern.patternDurationSec.toStringAsFixed(2)}');
    debugPrint('  gapBetweenPatterns=${pattern.gapBetweenPatterns.toStringAsFixed(2)}');

    // Build notes for each pattern repetition
    for (var k = 0; k < patternCount; k++) {
      final baseMidi = lowestMidi + k;
      
      // Calculate when this pattern starts in the visual timeline
      final patternStartSec = leadInSec + k * (pattern.patternDurationSec + pattern.gapBetweenPatterns);

      // Expand each note in the pattern
      for (final patternNote in pattern.notes) {
        final midi = baseMidi + patternNote.midiDelta;
        final startSec = patternStartSec + patternNote.xStart;
        final endSec = patternStartSec + patternNote.xEnd;

        visualNotes.add(ReferenceNote(
          startSec: startSec,
          endSec: endSec,
          midi: midi,
        ));
      }
    }

    final totalDurationSec = leadInSec + patternCount * (pattern.patternDurationSec + pattern.gapBetweenPatterns);
    debugPrint('[PatternVisualNoteBuilder] Built ${visualNotes.length} visual notes, totalDurationSec=${totalDurationSec.toStringAsFixed(2)}');
    debugPrint('[PatternVisualNoteBuilder] Pattern boundaries:');
    for (var k = 0; k < patternCount && k < 5; k++) {
      final baseMidi = lowestMidi + k;
      final patternStartSec = leadInSec + k * (pattern.patternDurationSec + pattern.gapBetweenPatterns);
      debugPrint('  Pattern $k: baseMidi=$baseMidi, startSec=${patternStartSec.toStringAsFixed(2)}');
    }
    if (patternCount > 5) {
      debugPrint('  ... (${patternCount - 5} more patterns)');
    }

    return visualNotes;
  }
}
