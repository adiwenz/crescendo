import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_mobile/services/exercise_plan_builder.dart';
import 'package:crescendo_mobile/models/vocal_exercise.dart';
import 'package:crescendo_mobile/models/pitch_highway_difficulty.dart';
import 'package:crescendo_mobile/models/pitch_highway_spec.dart';
import 'package:crescendo_mobile/models/pitch_segment.dart';

void main() {
  group('ExercisePlanBuilder.buildMetadata', () {
    test('builds correct transposed sequences from user range', () async {
      // Create a simple exercise with a single-note pattern
      final exercise = VocalExercise(
        id: 'test_exercise',
        name: 'Test Exercise',
        categoryId: 'test',
        type: ExerciseType.pitchHighway,
        description: 'Test',
        purpose: 'Test',
        difficulty: ExerciseDifficulty.beginner,
        tags: const [],
        createdAt: DateTime(2025, 1, 1),
        highwaySpec: PitchHighwaySpec(segments: [
          PitchSegment(startMs: 0, endMs: 500, midiNote: 60, toleranceCents: 50), // C
        ]),
      );

      final plan = await ExercisePlanBuilder.buildMetadata(
        exercise: exercise,
        lowestMidi: 60, // C4
        highestMidi: 62, // D4 (should get 3 transpositions: C, C#, D)
        difficulty: PitchHighwayDifficulty.easy,
        wavFilePath: '/test/path.wav',
      );

      // Should have notes for 3 transpositions
      // Transposition 1 (C): 60
      // Transposition 2 (C#): 61
      // Transposition 3 (D): 62
      expect(plan.notes.length, 3); // 1 note × 3 transpositions

      // Check transpositions
      expect(plan.notes[0].midi, 60);
      expect(plan.notes[1].midi, 61);
      expect(plan.notes[2].midi, 62);
    });

    test('increments by semitone and repeats pattern until top reached', () async {
      final exercise = VocalExercise(
        id: 'test',
        name: 'Test',
        categoryId: 'test',
        type: ExerciseType.pitchHighway,
        description: 'Test',
        purpose: 'Test',
        difficulty: ExerciseDifficulty.beginner,
        tags: const [],
        createdAt: DateTime(2025, 1, 1),
        highwaySpec: PitchHighwaySpec(segments: [
          PitchSegment(startMs: 0, endMs: 500, midiNote: 60, toleranceCents: 50),
        ]),
      );

      final plan = await ExercisePlanBuilder.buildMetadata(
        exercise: exercise,
        lowestMidi: 60,
        highestMidi: 64, // 5 semitones: 60, 61, 62, 63, 64
        difficulty: PitchHighwayDifficulty.easy,
        wavFilePath: '/test/path.wav',
      );

      expect(plan.notes.length, 5);
      expect(plan.notes[0].midi, 60);
      expect(plan.notes[1].midi, 61);
      expect(plan.notes[2].midi, 62);
      expect(plan.notes[3].midi, 63);
      expect(plan.notes[4].midi, 64);
    });

    test('produces deterministic metadata', () async {
      final exercise = VocalExercise(
        id: 'test',
        name: 'Test',
        categoryId: 'test',
        type: ExerciseType.pitchHighway,
        description: 'Test',
        purpose: 'Test',
        difficulty: ExerciseDifficulty.beginner,
        tags: const [],
        createdAt: DateTime(2025, 1, 1),
        highwaySpec: PitchHighwaySpec(segments: [
          PitchSegment(startMs: 0, endMs: 500, midiNote: 60, toleranceCents: 50),
        ]),
      );

      final plan1 = await ExercisePlanBuilder.buildMetadata(
        exercise: exercise,
        lowestMidi: 60,
        highestMidi: 62,
        difficulty: PitchHighwayDifficulty.easy,
        wavFilePath: '/test/path.wav',
      );

      final plan2 = await ExercisePlanBuilder.buildMetadata(
        exercise: exercise,
        lowestMidi: 60,
        highestMidi: 62,
        difficulty: PitchHighwayDifficulty.easy,
        wavFilePath: '/test/path.wav',
      );

      // Should produce identical results
      expect(plan1.durationMs, plan2.durationMs);
      expect(plan1.notes.length, plan2.notes.length);
      expect(plan1.rangeHash, plan2.rangeHash);
      expect(plan1.patternHash, plan2.patternHash);
    });

    test('timeline is monotonic and ends at expected duration', () async {
      final exercise = VocalExercise(
        id: 'test',
        name: 'Test',
        categoryId: 'test',
        type: ExerciseType.pitchHighway,
        description: 'Test',
        purpose: 'Test',
        difficulty: ExerciseDifficulty.beginner,
        tags: const [],
        createdAt: DateTime(2025, 1, 1),
        highwaySpec: PitchHighwaySpec(segments: [
          PitchSegment(startMs: 0, endMs: 500, midiNote: 60, toleranceCents: 50),
          PitchSegment(startMs: 500, endMs: 1000, midiNote: 64, toleranceCents: 50),
        ]),
      );

      final plan = await ExercisePlanBuilder.buildMetadata(
        exercise: exercise,
        lowestMidi: 60,
        highestMidi: 61,
        difficulty: PitchHighwayDifficulty.easy,
        wavFilePath: '/test/path.wav',
      );

      // Check timeline is monotonic (each note starts after or at the same time as previous)
      for (var i = 1; i < plan.notes.length; i++) {
        expect(
          plan.notes[i].startSec,
          greaterThanOrEqualTo(plan.notes[i - 1].startSec),
          reason: 'Note $i should start after note ${i - 1}',
        );
      }

      // Check duration is reasonable (last note end time + buffer)
      final lastNoteEnd = plan.notes.last.endSec;
      final expectedDuration = (lastNoteEnd + 1.0) * 1000; // 1s buffer
      expect(plan.durationMs, closeTo(expectedDuration, 100));
    });

    test('edge case: single-note range', () async {
      final exercise = VocalExercise(
        id: 'test',
        name: 'Test',
        categoryId: 'test',
        type: ExerciseType.pitchHighway,
        description: 'Test',
        purpose: 'Test',
        difficulty: ExerciseDifficulty.beginner,
        tags: const [],
        createdAt: DateTime(2025, 1, 1),
        highwaySpec: PitchHighwaySpec(segments: [
          PitchSegment(startMs: 0, endMs: 500, midiNote: 60, toleranceCents: 50),
        ]),
      );

      final plan = await ExercisePlanBuilder.buildMetadata(
        exercise: exercise,
        lowestMidi: 60,
        highestMidi: 60, // Same note
        difficulty: PitchHighwayDifficulty.easy,
        wavFilePath: '/test/path.wav',
      );

      // Should have exactly 1 note (one transposition)
      expect(plan.notes.length, 1);
      expect(plan.notes[0].midi, 60);
    });

    test('edge case: range smaller than pattern', () async {
      final exercise = VocalExercise(
        id: 'test',
        name: 'Test',
        categoryId: 'test',
        type: ExerciseType.pitchHighway,
        description: 'Test',
        purpose: 'Test',
        difficulty: ExerciseDifficulty.beginner,
        tags: const [],
        createdAt: DateTime(2025, 1, 1),
        highwaySpec: PitchHighwaySpec(segments: [
          PitchSegment(startMs: 0, endMs: 500, midiNote: 60, toleranceCents: 50),
          PitchSegment(startMs: 500, endMs: 1000, midiNote: 72, toleranceCents: 50), // Octave jump
        ]),
      );

      final plan = await ExercisePlanBuilder.buildMetadata(
        exercise: exercise,
        lowestMidi: 60,
        highestMidi: 61, // Only 2 semitones
        difficulty: PitchHighwayDifficulty.easy,
        wavFilePath: '/test/path.wav',
      );

      // Builder clamps and expands range to fit pattern, so we get 2 notes for one transposition
      expect(plan.notes.length, 2);
    });

    test('range hash changes with different ranges', () async {
      final exercise = VocalExercise(
        id: 'test',
        name: 'Test',
        categoryId: 'test',
        type: ExerciseType.pitchHighway,
        description: 'Test',
        purpose: 'Test',
        difficulty: ExerciseDifficulty.beginner,
        tags: const [],
        createdAt: DateTime(2025, 1, 1),
        highwaySpec: PitchHighwaySpec(segments: [
          PitchSegment(startMs: 0, endMs: 500, midiNote: 60, toleranceCents: 50),
        ]),
      );

      final plan1 = await ExercisePlanBuilder.buildMetadata(
        exercise: exercise,
        lowestMidi: 60,
        highestMidi: 62,
        difficulty: PitchHighwayDifficulty.easy,
        wavFilePath: '/test/path.wav',
      );

      final plan2 = await ExercisePlanBuilder.buildMetadata(
        exercise: exercise,
        lowestMidi: 61,
        highestMidi: 63,
        difficulty: PitchHighwayDifficulty.easy,
        wavFilePath: '/test/path.wav',
      );

      expect(plan1.rangeHash, isNot(equals(plan2.rangeHash)));
    });

    test('pattern hash changes with different exercises', () async {
      final exercise1 = VocalExercise(
        id: 'test1',
        name: 'Test 1',
        categoryId: 'test',
        type: ExerciseType.pitchHighway,
        description: 'Test',
        purpose: 'Test',
        difficulty: ExerciseDifficulty.beginner,
        tags: const [],
        createdAt: DateTime(2025, 1, 1),
        highwaySpec: PitchHighwaySpec(segments: [
          PitchSegment(startMs: 0, endMs: 500, midiNote: 60, toleranceCents: 50),
        ]),
      );

      final exercise2 = VocalExercise(
        id: 'test2',
        name: 'Test 2',
        categoryId: 'test',
        type: ExerciseType.pitchHighway,
        description: 'Test',
        purpose: 'Test',
        difficulty: ExerciseDifficulty.beginner,
        tags: const [],
        createdAt: DateTime(2025, 1, 1),
        highwaySpec: PitchHighwaySpec(segments: [
          PitchSegment(startMs: 0, endMs: 500, midiNote: 60, toleranceCents: 50),
        ]),
      );

      final plan1 = await ExercisePlanBuilder.buildMetadata(
        exercise: exercise1,
        lowestMidi: 60,
        highestMidi: 62,
        difficulty: PitchHighwayDifficulty.easy,
        wavFilePath: '/test/path.wav',
      );

      final plan2 = await ExercisePlanBuilder.buildMetadata(
        exercise: exercise2,
        lowestMidi: 60,
        highestMidi: 62,
        difficulty: PitchHighwayDifficulty.easy,
        wavFilePath: '/test/path.wav',
      );

      expect(plan1.patternHash, isNot(equals(plan2.patternHash)));
    });
  });
}
