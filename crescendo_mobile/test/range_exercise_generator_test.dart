import 'package:flutter_test/flutter_test.dart';

import 'package:crescendo_mobile/models/pitch_highway_spec.dart';
import 'package:crescendo_mobile/models/pitch_segment.dart';
import 'package:crescendo_mobile/models/vocal_exercise.dart';
import 'package:crescendo_mobile/services/range_exercise_generator.dart';

void main() {
  VocalExercise _exWithSpan(int minOffset, int maxOffset) {
    final base = 60;
    final seg = PitchSegment(
      startMs: 0,
      endMs: 1000,
      midiNote: base + maxOffset,
      toleranceCents: 25,
      startMidi: base + minOffset,
      endMidi: base + maxOffset,
    );
    return VocalExercise(
      id: 'ex',
      name: 'Test',
      categoryId: 'cat',
      type: ExerciseType.pitchHighway,
      description: '',
      purpose: '',
      difficulty: ExerciseDifficulty.beginner,
      tags: const [],
      createdAt: DateTime.now(),
      highwaySpec: PitchHighwaySpec(segments: [seg]),
    );
  }

  test('generates steps within bounds', () {
    final gen = RangeExerciseGenerator();
    final ex = _exWithSpan(0, 4);
    final out = gen.generate(exercise: ex, lowestMidi: 50, highestMidi: 70);
    expect(out, isNotEmpty);
    expect(out.first.minNote >= 52, true); // low margin applied
    expect(out.last.maxNote <= 68, true); // high margin applied
  });

  test('skips if out of range', () {
    final gen = RangeExerciseGenerator();
    final ex = _exWithSpan(0, 24);
    final out = gen.generate(exercise: ex, lowestMidi: 60, highestMidi: 62);
    expect(out, isEmpty);
  });
}
