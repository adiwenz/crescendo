import 'dart:math' as math;

import '../models/exercise_instance.dart';
import '../models/pitch_segment.dart';
import '../models/vocal_exercise.dart';

class SegmentRange {
  final int lowMidi;
  final int highMidi;

  const SegmentRange({required this.lowMidi, required this.highMidi});
}

class ExerciseSegment {
  final int transpositionSemitones;
  final int rootMidi;
  final List<int> notesMidi;
  final SegmentRange range;

  const ExerciseSegment({
    required this.transpositionSemitones,
    required this.rootMidi,
    required this.notesMidi,
    required this.range,
  });
}

class RangeExerciseGenerator {
  static const int safeMinMidi = 36;
  static const int safeMaxMidi = 84;

  List<ExerciseSegment> buildTransposedSegments({
    required List<int> patternOffsets,
    required int userLowestMidi,
    required int userHighestMidi,
    int stepSemitones = 1,
    bool allowOverhang = true,
  }) {
    if (patternOffsets.isEmpty) return const [];
    final patternMin = patternOffsets.reduce(math.min);
    final patternMax = patternOffsets.reduce(math.max);
    final firstRootMidi = userLowestMidi - patternMin;
    final segments = <ExerciseSegment>[];
    var t = 0;
    while (true) {
      final segmentLow = firstRootMidi + patternMin + t;
      final segmentHigh = firstRootMidi + patternMax + t;
      if (!allowOverhang && segmentHigh > userHighestMidi) break;
      if (segmentLow < safeMinMidi || segmentHigh > safeMaxMidi) {
        if (!allowOverhang) break;
        t += stepSemitones;
        if (stepSemitones <= 0) break;
        continue;
      }
      final notes = patternOffsets.map((o) => firstRootMidi + o + t).toList();
      segments.add(ExerciseSegment(
        transpositionSemitones: t,
        rootMidi: firstRootMidi + t,
        notesMidi: notes,
        range: SegmentRange(lowMidi: segmentLow, highMidi: segmentHigh),
      ));
      if (segmentHigh >= userHighestMidi) break;
      t += stepSemitones;
      if (stepSemitones <= 0) break;
    }
    if (segments.isEmpty && allowOverhang) {
      final low = firstRootMidi + patternMin;
      final high = firstRootMidi + patternMax;
      if (low >= safeMinMidi && high <= safeMaxMidi) {
        final notes = patternOffsets.map((o) => firstRootMidi + o).toList();
        segments.add(ExerciseSegment(
          transpositionSemitones: 0,
          rootMidi: firstRootMidi,
          notesMidi: notes,
          range: SegmentRange(lowMidi: low, highMidi: high),
        ));
      }
    }
    return segments;
  }

  List<ExerciseInstance> generate({
    required VocalExercise exercise,
    required int lowestMidi,
    required int highestMidi,
    int stepSemitones = 1,
  }) {
    if (exercise.highwaySpec == null || exercise.highwaySpec!.segments.isEmpty) {
      return const [];
    }
    final specSegments = exercise.highwaySpec!.segments;
    final baseRootMidi = _rootMidiFromSpec(specSegments);
    final offsets = _patternOffsets(specSegments, baseRootMidi);
    final builtSegments = buildTransposedSegments(
      patternOffsets: offsets,
      userLowestMidi: lowestMidi,
      userHighestMidi: highestMidi,
      stepSemitones: stepSemitones,
      allowOverhang: false,
    );
    return builtSegments.map((segment) {
      final transpose = segment.rootMidi - baseRootMidi;
      final label = 'Step ${segment.transpositionSemitones + 1}: ${_noteName(segment.rootMidi)}';
      return ExerciseInstance(
        baseExerciseId: exercise.id,
        transposeSemitones: transpose,
        minNote: segment.range.lowMidi,
        maxNote: segment.range.highMidi,
        label: label,
      );
    }).toList();
  }

  int _rootMidiFromSpec(List<PitchSegment> segments) {
    final first = segments.first;
    return first.startMidi ?? first.midiNote;
  }

  List<int> _patternOffsets(List<PitchSegment> segments, int baseRootMidi) {
    final offsets = <int>[];
    for (final seg in segments) {
      offsets.add(seg.midiNote - baseRootMidi);
      if (seg.startMidi != null) {
        offsets.add(seg.startMidi! - baseRootMidi);
      }
      if (seg.endMidi != null) {
        offsets.add(seg.endMidi! - baseRootMidi);
      }
    }
    return offsets;
  }

  String _noteName(int midi) {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (midi / 12).floor() - 1;
    return '${names[midi % 12]}$octave';
  }
}
