import 'dart:math' as math;

import '../models/exercise_instance.dart';
import '../models/pitch_segment.dart';
import '../models/vocal_exercise.dart';

class RangeExerciseGenerator {
  static const int lowMargin = 2;
  static const int highMargin = 2;
  static const int maxSteps = 20;
  static const int minSteps = 1;

  List<ExerciseInstance> generate({
    required VocalExercise exercise,
    required int lowestMidi,
    required int highestMidi,
    int stepSemitones = 1,
  }) {
    if (exercise.highwaySpec == null || exercise.highwaySpec!.segments.isEmpty) {
      return const [];
    }
    final bounds = _safeBounds(lowestMidi, highestMidi);
    final minOffset = exercise.highwaySpec!.segments
        .map(_segMinMidi)
        .reduce(math.min);
    final maxOffset = exercise.highwaySpec!.segments
        .map(_segMaxMidi)
        .reduce(math.max);
    final rootMin = bounds.$1 - minOffset;
    final rootMax = bounds.$2 - maxOffset;
    if (rootMin > rootMax) return const [];
    final roots = <int>[];
    for (var r = rootMin; r <= rootMax; r += stepSemitones) {
      roots.add(r);
      if (roots.length >= maxSteps) break;
    }
    if (roots.isEmpty) return const [];
    final instances = roots.map((root) {
      final minNote = root + minOffset;
      final maxNote = root + maxOffset;
      final label = 'Step ${roots.indexOf(root) + 1}: ${_noteName(root)}';
      return ExerciseInstance(
        baseExerciseId: exercise.id,
        transposeSemitones: root - minOffset,
        minNote: minNote,
        maxNote: maxNote,
        label: label,
      );
    }).toList();
    return instances;
  }

  (int, int) _safeBounds(int low, int high) {
    final lb = low + lowMargin;
    final hb = high - highMargin;
    if (lb >= hb) return (low, high);
    return (lb, hb);
  }

  int _segMinMidi(PitchSegment seg) {
    return math.min(seg.startMidi ?? seg.midiNote, math.min(seg.endMidi ?? seg.midiNote, seg.midiNote));
  }

  int _segMaxMidi(PitchSegment seg) {
    return math.max(seg.startMidi ?? seg.midiNote, math.max(seg.endMidi ?? seg.midiNote, seg.midiNote));
  }

  String _noteName(int midi) {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (midi / 12).floor() - 1;
    return '${names[midi % 12]}$octave';
  }
}
