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
  static const bool enableRangeGeneration = true;

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
    // Start the root note (starting note) at userLowestMidi
    // The root note corresponds to offset 0 in patternOffsets
    // If the pattern has notes below the root (patternMin < 0), adjust so the lowest note is at userLowestMidi
    // Otherwise, the root starts at userLowestMidi
    final firstRootMidi = patternMin < 0 ? userLowestMidi - patternMin : userLowestMidi;
    final segments = <ExerciseSegment>[];
    var t = 0;
    while (true) {
      final segmentLow = firstRootMidi + patternMin + t;
      final segmentHigh = firstRootMidi + patternMax + t;
      // Ensure the lowest note is at least userLowestMidi (starting note requirement)
      if (segmentLow < userLowestMidi) {
        // Skip this iteration if it would go below the starting note
        t += stepSemitones;
        if (stepSemitones <= 0) break;
        continue;
      }
      // Stop if the highest note would exceed userHighestMidi
      if (!allowOverhang && segmentHigh > userHighestMidi) break;
      // Skip if outside safe MIDI range
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
      // Stop when we've reached or exceeded the highest note
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
    if (!enableRangeGeneration) {
      final range = _segmentMidiRange(specSegments);
      return [
        ExerciseInstance(
          baseExerciseId: exercise.id,
          transposeSemitones: 0,
          minNote: range.lowMidi,
          maxNote: range.highMidi,
          label: 'Base: ${_noteName(baseRootMidi)}',
        ),
      ];
    }
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

  SegmentRange _segmentMidiRange(List<PitchSegment> segments) {
    var minMidi = segments.first.midiNote;
    var maxMidi = segments.first.midiNote;
    for (final seg in segments) {
      minMidi = math.min(minMidi, seg.midiNote);
      maxMidi = math.max(maxMidi, seg.midiNote);
      if (seg.startMidi != null) {
        minMidi = math.min(minMidi, seg.startMidi!);
        maxMidi = math.max(maxMidi, seg.startMidi!);
      }
      if (seg.endMidi != null) {
        minMidi = math.min(minMidi, seg.endMidi!);
        maxMidi = math.max(maxMidi, seg.endMidi!);
      }
    }
    return SegmentRange(lowMidi: minMidi, highMidi: maxMidi);
  }

  String _noteName(int midi) {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (midi / 12).floor() - 1;
    return '${names[midi % 12]}$octave';
  }
}
