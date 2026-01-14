import 'dart:math' as math;

import '../models/pitch_highway_difficulty.dart';
import '../models/pitch_segment.dart';
import '../models/reference_note.dart';
import '../models/vocal_exercise.dart';
import '../utils/pitch_highway_tempo.dart';

/// Builds a complete transposed exercise sequence that starts at the user's lowest note
/// and steps up by semitones until reaching the highest note.
class TransposedExerciseBuilder {
  /// Builds reference notes for the full transposed exercise sequence.
  /// 
  /// The exercise pattern is repeated multiple times, each time transposed up by one semitone.
  /// The sequence starts at the user's lowestNote and continues until the highest pitch
  /// of the exercise equals the user's highestNote.
  static List<ReferenceNote> buildTransposedSequence({
    required VocalExercise exercise,
    required int lowestMidi,
    required int highestMidi,
    required double leadInSec,
    PitchHighwayDifficulty? difficulty,
  }) {
    final spec = exercise.highwaySpec;
    if (spec == null || spec.segments.isEmpty) return const [];

    // Apply tempo scaling if difficulty is provided
    final multiplier = difficulty != null
        ? PitchHighwayTempo.multiplierFor(difficulty, spec.segments)
        : 1.0;
    final scaledSegments = difficulty != null
        ? PitchHighwayTempo.scaleSegments(spec.segments, multiplier)
        : spec.segments;

    // Find the base root note (first note of the pattern)
    final baseRootMidi = _getBaseRootMidi(scaledSegments);
    
    // Extract pattern offsets relative to the root
    final patternOffsets = _extractPatternOffsets(scaledSegments, baseRootMidi);
    if (patternOffsets.isEmpty) return const [];

    // Find the min and max offsets in the pattern
    final patternMin = patternOffsets.reduce(math.min);
    final patternMax = patternOffsets.reduce(math.max);

    // Calculate how many semitones we need to transpose
    // Start so the lowest note of the first repetition equals lowestMidi
    // Continue until the highest note of a repetition equals highestMidi
    final firstRootMidi = patternMin < 0 ? lowestMidi - patternMin : lowestMidi;
    
    // Calculate the duration of one repetition of the pattern
    final patternDurationMs = scaledSegments.isEmpty
        ? 0
        : scaledSegments.map((s) => s.endMs).reduce(math.max);
    final patternDurationSec = patternDurationMs / 1000.0;
    const gapBetweenRepetitionsSec = 0.75;

    // Build all transposed repetitions
    final allNotes = <ReferenceNote>[];
    var transpositionSemitones = 0;
    var currentTimeSec = leadInSec;

    while (true) {
      final rootMidi = firstRootMidi + transpositionSemitones;
      final segmentLow = rootMidi + patternMin;
      final segmentHigh = rootMidi + patternMax;

      // Stop if we would exceed the highest note
      if (segmentHigh > highestMidi) break;
      
      // Skip if we would go below the lowest note (shouldn't happen, but safety check)
      if (segmentLow < lowestMidi) {
        transpositionSemitones++;
        continue;
      }

      // Build notes for this transposition
      final repetitionNotes = _buildNotesForTransposition(
        segments: scaledSegments,
        baseRootMidi: baseRootMidi,
        transpositionSemitones: transpositionSemitones,
        startTimeSec: currentTimeSec,
      );
      
      allNotes.addAll(repetitionNotes);
      
      // Update time for next repetition - add pattern duration plus gap
      currentTimeSec += patternDurationSec + gapBetweenRepetitionsSec;

      // Move to next semitone
      transpositionSemitones++;
      
      // Safety check to prevent infinite loops
      if (transpositionSemitones > 100) break;
    }

    return allNotes;
  }

  /// Gets the base root MIDI note from the segments (the first note's MIDI value)
  static int _getBaseRootMidi(List<PitchSegment> segments) {
    if (segments.isEmpty) return 60; // Default to C4
    final first = segments.first;
    return first.startMidi ?? first.midiNote;
  }

  /// Extracts pattern offsets relative to the base root note
  static List<int> _extractPatternOffsets(List<PitchSegment> segments, int baseRootMidi) {
    final offsets = <int>{};
    for (final seg in segments) {
      offsets.add(seg.midiNote - baseRootMidi);
      if (seg.startMidi != null) {
        offsets.add(seg.startMidi! - baseRootMidi);
      }
      if (seg.endMidi != null) {
        offsets.add(seg.endMidi! - baseRootMidi);
      }
    }
    return offsets.toList();
  }

  /// Builds reference notes for a single transposition of the exercise
  static List<ReferenceNote> _buildNotesForTransposition({
    required List<PitchSegment> segments,
    required int baseRootMidi,
    required int transpositionSemitones,
    required double startTimeSec,
  }) {
    final notes = <ReferenceNote>[];

    for (final seg in segments) {
      // Segments have absolute times within the pattern (startMs, endMs)
      // Convert to seconds and offset by startTimeSec
      final segStartSec = startTimeSec + (seg.startMs / 1000.0);
      final segEndSec = startTimeSec + (seg.endMs / 1000.0);
      final durationSec = segEndSec - segStartSec;
      
      if (seg.isGlide) {
        final startMidi = (seg.startMidi ?? seg.midiNote) + transpositionSemitones;
        final endMidi = (seg.endMidi ?? seg.midiNote) + transpositionSemitones;
        final steps = math.max(4, (seg.endMs - seg.startMs) ~/ 200);
        
        for (var i = 0; i < steps; i++) {
          final ratio = i / steps;
          final midi = (startMidi + (endMidi - startMidi) * ratio).round();
          final stepStart = segStartSec + (durationSec * ratio);
          final stepEnd = segStartSec + (durationSec * ((i + 1) / steps));
          
          notes.add(ReferenceNote(
            startSec: stepStart,
            endSec: stepEnd,
            midi: midi,
            lyric: seg.label,
          ));
        }
      } else {
        final midi = seg.midiNote + transpositionSemitones;
        notes.add(ReferenceNote(
          startSec: segStartSec,
          endSec: segEndSec,
          midi: midi,
          lyric: seg.label,
        ));
      }
    }

    return notes;
  }
}
