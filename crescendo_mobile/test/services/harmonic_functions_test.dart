import 'package:crescendo_mobile/models/harmonic_models.dart';
import 'package:crescendo_mobile/models/reference_note.dart';
import 'package:crescendo_mobile/services/harmonic_functions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HarmonicFunctions', () {
    test('getChordNotes - C Major I (C E G)', () {
      final keyRoot = 60; // C4
      final notes = HarmonicFunctions.getChordNotes(
        chord: Chord.I_Major,
        keyRootMidi: keyRoot,
      );
      // Root: C4 (60) - 12 (octave down) = 48 (C3)
      // Structure: 0, 4, 7 -> 48, 52, 55 (C3, E3, G3)
      expect(notes, [48, 52, 55]);
    });

    test('getChordNotes - C Major V (G B D)', () {
      final keyRoot = 60; // C4
      final notes = HarmonicFunctions.getChordNotes(
        chord: Chord.V_Major,
        keyRootMidi: keyRoot,
      );
      // Root: G4 (60+7=67) - 12 = 55 (G3)
      // Structure: 0, 4, 7 -> 55, 59, 62 (G3, B3, D4)
      expect(notes, [55, 59, 62]);
    });

    test('getChordNotes - C Minor i (C Eb G)', () {
      final keyRoot = 60; // C4
      // i minor in minor key
      final notes = HarmonicFunctions.getChordNotes(
        chord: Chord(root: ScaleDegree.I, quality: ChordQuality.minor),
        keyRootMidi: keyRoot,
        isMinorKey: true,
      );
      // Root: 60 - 12 = 48
      // Minor structure: 0, 3, 7 -> 48, 51, 55 (C3, Eb3, G3)
      expect(notes, [48, 51, 55]);
    });

    test('generateHarmonyForKey - Modulation check', () {
      final progression = [
        ChordEvent(chord: Chord.I_Major, startMs: 0, durationMs: 1000),
      ];
      
      // Key C (60)
      final notesC = HarmonicFunctions.generateHarmonyForKey(
        progression: progression,
        keyRootMidi: 60,
        startTimeSec: 0,
      );
      expect(notesC.first.midi, 48); // C3
      
      // Key C# (61)
      final notesCsharp = HarmonicFunctions.generateHarmonyForKey(
        progression: progression,
        keyRootMidi: 61,
        startTimeSec: 2.0,
      );
      expect(notesCsharp.first.midi, 49); // C#3
      expect(notesCsharp.first.startSec, 2.0);
    });
  });
}
