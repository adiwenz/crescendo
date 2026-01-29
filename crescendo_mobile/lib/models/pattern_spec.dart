/// Pattern specification loaded from JSON for visual note rendering.
class PatternSpec {
  final int schemaVersion;
  final String exerciseId;
  final String patternId;
  final int noteCount;
  final double patternDurationSec;
  final double gapBetweenPatterns;
  final List<PatternNote> notes;

  PatternSpec({
    required this.schemaVersion,
    required this.exerciseId,
    required this.patternId,
    required this.noteCount,
    required this.patternDurationSec,
    required this.gapBetweenPatterns,
    required this.notes,
  });

  factory PatternSpec.fromJson(Map<String, dynamic> json) {
    final notesJson = json['notes'] as List<dynamic>;
    return PatternSpec(
      schemaVersion: json['schemaVersion'] as int,
      exerciseId: json['exerciseId'] as String,
      patternId: json['patternId'] as String,
      noteCount: json['noteCount'] as int,
      patternDurationSec: (json['patternDurationSec'] as num).toDouble(),
      gapBetweenPatterns: (json['gapBetweenPatterns'] as num).toDouble(),
      notes: notesJson
          .map((n) => PatternNote.fromJson(n as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Get the maximum midiDelta in the pattern (for range calculation)
  int get maxMidiDelta {
    if (notes.isEmpty) return 0;
    return notes.map((n) => n.midiDelta).reduce((a, b) => a > b ? a : b);
  }
}

/// A single note within a pattern (relative timing and MIDI delta).
class PatternNote {
  final int i;
  final int midiDelta;
  final double xStart;
  final double xEnd;

  PatternNote({
    required this.i,
    required this.midiDelta,
    required this.xStart,
    required this.xEnd,
  });

  factory PatternNote.fromJson(Map<String, dynamic> json) {
    return PatternNote(
      i: json['i'] as int,
      midiDelta: json['midiDelta'] as int,
      xStart: (json['xStart'] as num).toDouble(),
      xEnd: (json['xEnd'] as num).toDouble(),
    );
  }
}
