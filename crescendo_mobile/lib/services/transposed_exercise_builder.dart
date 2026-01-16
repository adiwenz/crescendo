import 'dart:math' as math;

import '../models/pitch_highway_difficulty.dart';
import '../models/pitch_segment.dart';
import '../models/reference_note.dart';
import '../models/vocal_exercise.dart';
import '../utils/pitch_highway_tempo.dart';
import '../utils/exercise_constants.dart';

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
    double? leadInSec,
    PitchHighwayDifficulty? difficulty,
  }) {
    // Use shared constant if leadInSec not provided
    final effectiveLeadInSec = leadInSec ?? ExerciseConstants.leadInSec;
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
    // Sirens need 2s rest between cycles, others use 0.75s
    final gapBetweenRepetitionsSec = exercise.id == 'sirens' ? 2.0 : 0.75;

    // Build all transposed repetitions
    final allNotes = <ReferenceNote>[];
    var transpositionSemitones = 0;
    var currentTimeSec = effectiveLeadInSec;

    // Validation logging (temporary)
    // ignore: avoid_print
    print('[TransposedExerciseBuilder] Range: lowestMidi=$lowestMidi, highestMidi=$highestMidi');
    // ignore: avoid_print
    print('[TransposedExerciseBuilder] Pattern: baseRootMidi=$baseRootMidi, patternMin=$patternMin, patternMax=$patternMax');
    // ignore: avoid_print
    print('[TransposedExerciseBuilder] First root MIDI: $firstRootMidi');

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

      // Calculate the actual transposition needed: from baseRootMidi to rootMidi
      final actualTransposition = rootMidi - baseRootMidi;

      // Build notes for this transposition
      final repetitionNotes = _buildNotesForTransposition(
        segments: scaledSegments,
        baseRootMidi: baseRootMidi,
        actualTranspositionSemitones: actualTransposition,
        startTimeSec: currentTimeSec,
        exerciseId: exercise.id,
      );
      
      allNotes.addAll(repetitionNotes);
      
      // Update time for next repetition - add pattern duration plus gap
      currentTimeSec += patternDurationSec + gapBetweenRepetitionsSec;

      // Move to next semitone
      transpositionSemitones++;
      
      // Safety check to prevent infinite loops
      if (transpositionSemitones > 100) break;
    }

    // Validation assertions
    if (allNotes.isNotEmpty) {
      final firstTargetMidi = allNotes.first.midi.round();
      final lastTargetMidi = allNotes.last.midi.round();
      // ignore: avoid_print
      print('[TransposedExerciseBuilder] Generated notes: firstTargetMidi=$firstTargetMidi, lastTargetMidi=$lastTargetMidi');
      
      // Assert: first note should be at or near lowestMidi (accounting for pattern offsets)
      final expectedFirstMidi = lowestMidi + patternMin;
      assert(
        (firstTargetMidi - expectedFirstMidi).abs() <= 1,
        'First target MIDI ($firstTargetMidi) should be near expected ($expectedFirstMidi) based on lowestMidi ($lowestMidi)',
      );
    }

    return allNotes;
  }

  /// Gets the base root MIDI note from the segments (the first note's MIDI value)
  /// Throws if segments are empty - range must be validated before calling this
  static int _getBaseRootMidi(List<PitchSegment> segments) {
    if (segments.isEmpty) {
      throw ArgumentError('Cannot get base root MIDI from empty segments');
    }
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
  /// 
  /// [actualTranspositionSemitones] is the number of semitones to transpose from the base root
  /// to the target root for this repetition (e.g., if base is C4=60 and target is B2=47, 
  /// transposition is -13 semitones)
  static List<ReferenceNote> _buildNotesForTransposition({
    required List<PitchSegment> segments,
    required int baseRootMidi,
    required int actualTranspositionSemitones,
    required double startTimeSec,
    String? exerciseId, // Add exercise ID to detect NG Slides and Sirens
  }) {
    final notes = <ReferenceNote>[];
    final isNgSlides = exerciseId == 'ng_slides';
    final isSirens = exerciseId == 'sirens';

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      // Segments have absolute times within the pattern (startMs, endMs)
      // Convert to seconds and offset by startTimeSec
      final segStartSec = startTimeSec + (seg.startMs / 1000.0);
      final segEndSec = startTimeSec + (seg.endMs / 1000.0);
      
      if (seg.isGlide) {
        // For NG Slides and Sirens: create full-length notes for audio, but mark for visual glide
        if (isNgSlides || isSirens) {
          final midi = seg.midiNote + actualTranspositionSemitones;
          final isFirstSegment = i == 0;
          final endMidi = (seg.endMidi ?? seg.midiNote) + actualTranspositionSemitones;
          
          // Create full-length note for audio playback
          notes.add(ReferenceNote(
            startSec: segStartSec,
            endSec: segEndSec,
            midi: midi, // Use the segment's midiNote for audio
            lyric: seg.label,
            // Mark first glide segment as glide start for visual rendering
            isGlideStart: isFirstSegment,
            glideEndMidi: isFirstSegment ? endMidi : null,
          ));
        } else {
          // For other glides: create endpoint notes (original behavior)
          final startMidi = (seg.startMidi ?? seg.midiNote) + actualTranspositionSemitones;
          final endMidi = (seg.endMidi ?? seg.midiNote) + actualTranspositionSemitones;
          
          // Start endpoint note (very short duration, just to mark the position)
          notes.add(ReferenceNote(
            startSec: segStartSec,
            endSec: segStartSec + 0.01, // Very short to mark position
            midi: startMidi,
            lyric: seg.label,
            isGlideStart: true,
            glideEndMidi: endMidi,
          ));
          
          // End endpoint note
          notes.add(ReferenceNote(
            startSec: segEndSec - 0.01,
            endSec: segEndSec,
            midi: endMidi,
            lyric: seg.label,
            isGlideEnd: true,
          ));
        }
      } else {
        final midi = seg.midiNote + actualTranspositionSemitones;
        notes.add(ReferenceNote(
          startSec: segStartSec,
          endSec: segEndSec,
          midi: midi,
          lyric: seg.label,
        ));
      }
    }
    
    // For Sirens: mark the top note (second) as glide end for first glide, and last note as glide end for second glide
    if (isSirens && notes.length >= 3) {
      // First glide: bottom1 -> top (top note should be marked as glide end)
      final topNote = notes[1];
      notes[1] = ReferenceNote(
        startSec: topNote.startSec,
        endSec: topNote.endSec,
        midi: topNote.midi,
        lyric: topNote.lyric,
        isGlideEnd: true, // End of first glide (bottom1 -> top)
        isGlideStart: true, // Start of second glide (top -> bottom2)
        glideEndMidi: notes[2].midi, // End of second glide is bottom2
      );
      // Second glide: top -> bottom2 (bottom2 note should be marked as glide end)
      final lastNote = notes.last;
      notes[notes.length - 1] = ReferenceNote(
        startSec: lastNote.startSec,
        endSec: lastNote.endSec,
        midi: lastNote.midi,
        lyric: lastNote.lyric,
        isGlideEnd: true, // End of second glide (top -> bottom2)
      );
    }

    return notes;
  }
}
