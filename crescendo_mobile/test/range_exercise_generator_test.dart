import 'package:flutter_test/flutter_test.dart';

import 'package:crescendo_mobile/services/range_exercise_generator.dart';

void main() {
  test('builds continuous semitone steps across range', () {
    final gen = RangeExerciseGenerator();
    final offsets = [0, 2, 4, 5, 7, 5, 4, 2, 0];
    final segments = gen.buildTransposedSegments(
      patternOffsets: offsets,
      userLowestMidi: 50,
      userHighestMidi: 60,
      stepSemitones: 1,
      allowOverhang: false,
    );
    expect(segments, isNotEmpty);
    expect(segments.first.range.lowMidi, 50);
    expect(segments.last.range.highMidi <= 60, true);
    for (var i = 1; i < segments.length; i++) {
      expect(segments[i].rootMidi - segments[i - 1].rootMidi, 1);
    }
  });

  test('anchors first segment to user low even if range is tight', () {
    final gen = RangeExerciseGenerator();
    final offsets = [0, 2, 4, 7];
    final segments = gen.buildTransposedSegments(
      patternOffsets: offsets,
      userLowestMidi: 55,
      userHighestMidi: 57,
      stepSemitones: 1,
      allowOverhang: true,
    );
    expect(segments, isNotEmpty);
    expect(segments.first.range.lowMidi, 55);
  });
}
