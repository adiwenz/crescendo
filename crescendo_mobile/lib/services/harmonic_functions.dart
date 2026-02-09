import '../models/harmonic_models.dart';
import '../models/reference_note.dart';

class HarmonicFunctions {
  /// Returns the MIDI notes for a given chord within a key.
  /// 
  /// [chord] The chord definition (scale degree, quality).
  /// [keyRootMidi] The MIDI note of the key's tonic (e.g., C4 = 60).
  /// [isMinorKey] Whether the key is minor (affects interval calculation).
  /// [octaveOffset] Octave shift for voicing (default -1 to play below melody).
  /// 
  /// Returns a list of MIDI note numbers.
  static List<int> getChordNotes({
    required Chord chord,
    required int keyRootMidi,
    bool isMinorKey = false,
    int octaveOffset = -1,
  }) {
    // 1. Determine the root note of the chord relative to the key tonic
    // Major scale intervals: 0, 2, 4, 5, 7, 9, 11
    // Minor scale intervals (natural): 0, 2, 3, 5, 7, 8, 10
    final scaleIntervals = isMinorKey 
        ? [0, 2, 3, 5, 7, 8, 10] 
        : [0, 2, 4, 5, 7, 9, 11];
    
    // Get the interval from the tonic to the chord root
    // Degree is 1-based (1..7)
    final degreeIndex = (chord.root.degree - 1) % 7;
    final scaleInterval = scaleIntervals[degreeIndex];
    
    // Apply accidental (flat/sharp) from ScaleDegree
    final rootInterval = scaleInterval + chord.root.accidental;
    
    final chordRootMidi = keyRootMidi + rootInterval + (octaveOffset * 12);
    
    // 2. Build the chord structure based on quality
    // Intervals relative to the CHORD ROOT
    final structure = _getChordStructure(chord.quality);
    
    return structure.map((interval) => chordRootMidi + interval).toList();
  }

  static List<int> _getChordStructure(ChordQuality quality) {
    switch (quality) {
      case ChordQuality.major:
        return [0, 4, 7]; // Root, Major 3rd, Perfect 5th
      case ChordQuality.minor:
        return [0, 3, 7]; // Root, Minor 3rd, Perfect 5th
      case ChordQuality.diminished:
        return [0, 3, 6]; // Root, Minor 3rd, Diminished 5th
      case ChordQuality.augmented:
        return [0, 4, 8]; // Root, Major 3rd, Augmented 5th
      case ChordQuality.dominant7:
        return [0, 4, 7, 10]; // Root, Maj 3, P5, min 7
      case ChordQuality.major7:
        return [0, 4, 7, 11]; // Root, Maj 3, P5, Maj 7
      case ChordQuality.minor7:
        return [0, 3, 7, 10]; // Root, min 3, P5, min 7
      case ChordQuality.sus4:
        return [0, 5, 7]; // Root, P4, P5
      case ChordQuality.sus2:
        return [0, 2, 7]; // Root, Maj 2, P5
    }
  }

  /// Generates ReferenceNotes for a single iteration of the chord progression.
  /// 
  /// [progression] List of ChordEvents defining the harmonic rhythm.
  /// [keyRootMidi] The tonic of the current key.
  /// [startTimeSec] Absolute start time of this pattern iteration in the exercise.
  static List<ReferenceNote> generateHarmonyForKey({
    required List<ChordEvent> progression,
    required int keyRootMidi,
    required double startTimeSec,
    bool isMinorKey = false,
  }) {
    final notes = <ReferenceNote>[];
    
    for (final event in progression) {
      final chordMidis = getChordNotes(
        chord: event.chord,
        keyRootMidi: keyRootMidi,
        isMinorKey: isMinorKey,
      );
      
      final start = startTimeSec + (event.startMs / 1000.0);
      final end = start + (event.durationMs / 1000.0);
      
      for (final midi in chordMidis) {
        notes.add(ReferenceNote(
          startSec: start,
          endSec: end,
          midi: midi,
          // No lyric for harmony notes usually
        ));
      }
    }
    
    return notes;
  }
}
