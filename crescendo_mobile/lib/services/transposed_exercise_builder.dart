import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;

import '../models/pitch_highway_difficulty.dart';
import '../models/pitch_segment.dart';
import '../models/reference_note.dart';
import '../models/siren_exercise_result.dart';
import '../models/siren_path.dart';
import '../models/vocal_exercise.dart';
import '../utils/pitch_highway_tempo.dart';
import '../utils/exercise_constants.dart';
import '../utils/pitch_math.dart';

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
    
    // Special handling for Sirens: generate visual path + minimal audio notes
    // Note: For Sirens, we need to return a different structure, but for now
    // we'll keep the same return type and handle it in the caller
    // TODO: Refactor to return SirenExerciseResult for Sirens
    if (exercise.id == 'sirens') {
      // This will be handled separately - return empty for now
      // The actual Sirens building happens in _buildSirensWithVisualPath
      return const [];
    }

    // Calculate the duration of one repetition of the pattern
    final patternDurationMs = scaledSegments.isEmpty
        ? 0
        : scaledSegments.map((s) => s.endMs).reduce(math.max);
    final patternDurationSec = patternDurationMs / 1000.0;
    // Gap between repetitions
    final gapBetweenRepetitionsSec = 0.75;

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
      final firstNoteName = PitchMath.midiToName(firstTargetMidi);
      // ignore: avoid_print
      print('[TransposedExerciseBuilder] Generated notes: firstTargetMidi=$firstTargetMidi ($firstNoteName), lastTargetMidi=$lastTargetMidi');
      
      // Assert: first note should be at or near lowestMidi (accounting for pattern offsets)
      final expectedFirstMidi = lowestMidi + patternMin;
      final expectedNoteName = PitchMath.midiToName(expectedFirstMidi);
      final midiDiff = (firstTargetMidi - expectedFirstMidi).abs();
      
      // Octave tripwire: detect if first note is exactly +12 semitones off
      if (midiDiff == 12) {
        debugPrint(
            '[TransposedExerciseBuilder] ⚠️ OCTAVE SHIFT DETECTED in note generation: '
            'exerciseId=${exercise.id}, baseRootMidi=$baseRootMidi, '
            'lowestMidi=$lowestMidi, patternMin=$patternMin, '
            'expectedFirstMidi=$expectedFirstMidi ($expectedNoteName), '
            'actualFirstMidi=$firstTargetMidi ($firstNoteName), '
            'shift=+${midiDiff} semitones (one octave too high)');
        debugPrint('[TransposedExerciseBuilder] Stack trace: ${StackTrace.current}');
      }
      
      assert(
        (firstTargetMidi - expectedFirstMidi).abs() <= 1,
        'First target MIDI ($firstTargetMidi/$firstNoteName) should be near expected ($expectedFirstMidi/$expectedNoteName) based on lowestMidi ($lowestMidi). '
        'Difference: ${midiDiff} semitones${midiDiff == 12 ? " (OCTAVE SHIFT BUG!)" : ""}',
      );
    }

    return allNotes;
  }

  /// Gets the base root MIDI note from the segments (the first note's MIDI value)
  /// Uses midiNote (audio note) rather than startMidi (visual glide start) for transposition calculations
  /// Throws if segments are empty - range must be validated before calling this
  static int _getBaseRootMidi(List<PitchSegment> segments) {
    if (segments.isEmpty) {
      throw ArgumentError('Cannot get base root MIDI from empty segments');
    }
    final first = segments.first;
    // Use midiNote (audio note) for transposition, not startMidi (visual glide)
    return first.midiNote;
  }

  /// Extracts pattern offsets relative to the base root note
  /// Uses only midiNote and endMidi (audio notes), not startMidi (visual glide start)
  static List<int> _extractPatternOffsets(List<PitchSegment> segments, int baseRootMidi) {
    final offsets = <int>{};
    for (final seg in segments) {
      // Use midiNote (audio note) for pattern offsets
      offsets.add(seg.midiNote - baseRootMidi);
      // Include endMidi if present (for glides, this is the audio end note)
      if (seg.endMidi != null) {
        offsets.add(seg.endMidi! - baseRootMidi);
      }
      // Do NOT include startMidi - it's for visual glides only, not audio transposition
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

  /// Builds a Sirens exercise with separate visual path and minimal audio notes
  /// Returns visual path (high-res control points) + 3 audio notes (bottom, top, bottom)
  /// Each cycle is a bell curve: starts at cycleStartMidi, goes up to highestMidi, returns to cycleStartMidi
  /// Cycles transpose up by 1 semitone: cycle 1 starts at lowestMidi, cycle 2 at lowestMidi+1, etc.
  static SirenExerciseResult buildSirensWithVisualPath({
    required VocalExercise exercise,
    required int lowestMidi,
    required int highestMidi,
    required double leadInSec,
    PitchHighwayDifficulty? difficulty,
  }) {
    final spec = exercise.highwaySpec;
    if (spec == null || spec.segments.isEmpty) {
      return const SirenExerciseResult(
        visualPath: SirenPath(points: []),
        audioNotes: [],
      );
    }

    // Extract pattern duration from spec (one cycle: bottom->top->bottom)
    final patternDurationMs = spec.segments
        .map((s) => s.endMs)
        .reduce((a, b) => a > b ? a : b);
    final patternDurationSec = patternDurationMs / 1000.0;
    
    // Apply tempo scaling if difficulty is provided
    final multiplier = difficulty != null
        ? PitchHighwayTempo.multiplierFor(difficulty, spec.segments)
        : 1.0;
    final scaledPatternDurationSec = patternDurationSec * multiplier;
    
    // Fixed siren range: C4 to E5 (approximately 16 semitones)
    // This gives a consistent range similar to the original pattern
    const sirenRangeSemitones = 16; // C4 (60) to E5 (76) = 16 semitones
    
    // Calculate how many cycles fit: start at lowestMidi, transpose up by 1 semitone each cycle
    // Continue until (cycleStartMidi + sirenRangeSemitones) > highestMidi
    // This ensures the transposed highest note doesn't exceed the saved range
    final cyclesNeeded = (highestMidi - lowestMidi - sirenRangeSemitones + 1).clamp(1, 100);
    
    // Timing constants
    const noteSpacingSec = 1.5; // 1.5 seconds between each note (bottom -> top -> bottom)
    const gapBetweenCyclesSec = 2.0; // 2 seconds between cycles
    const noteDurationSec = 0.5; // Each note duration
    
    // Calculate cycle duration: 3 notes with 1.5s spacing = 2 gaps of 1.5s = 3.0s
    // Plus note durations (3 notes * 0.5s = 1.5s)
    // Total cycle duration: 4.5s, but use pattern duration from spec for visual consistency
    final cycleDurationSec = scaledPatternDurationSec;
    
    // Generate visual path points (60 Hz for smooth curves)
    const sampleRateHz = 60.0;
    const sampleIntervalSec = 1.0 / sampleRateHz;
    
    final visualPoints = <SirenPoint>[];
    final audioNotes = <ReferenceNote>[];
    var currentTimeSec = leadInSec;
    
    // Build cycles, each starting one semitone higher
    for (var cycleIndex = 0; cycleIndex < cyclesNeeded; cycleIndex++) {
      final cycleStartMidi = lowestMidi + cycleIndex;
      final cycleEndMidi = cycleStartMidi + sirenRangeSemitones;
      
      // Stop if transposed highest note exceeds highestMidi
      if (cycleEndMidi > highestMidi) break;
      
      // Each cycle: cycleStartMidi -> cycleEndMidi -> cycleStartMidi (bell curve)
      final cycleRange = sirenRangeSemitones;
      
      // Generate bell curve for visual path: smooth up and down, symmetric
      // Use sine wave from 0 to π for smooth bell curve shape
      final numSamples = (cycleDurationSec / sampleIntervalSec).ceil();
      for (var i = 0; i < numSamples; i++) {
        final tNorm = i / (numSamples - 1); // Normalized time [0..1]
        // Bell curve: sin(π * t) gives us 0 at t=0, 1 at t=0.5, 0 at t=1
        // Map to MIDI: cycleStartMidi at t=0 and t=1, cycleEndMidi at t=0.5
        final bellCurve = math.sin(math.pi * tNorm); // 0 -> 1 -> 0
        final midiFloat = cycleStartMidi + (cycleRange * bellCurve);
        final tSec = currentTimeSec + (tNorm * cycleDurationSec);
        visualPoints.add(SirenPoint(tSec: tSec, midiFloat: midiFloat));
      }
      
      // Generate 3 audio notes with 1.5s spacing between each
      // Bottom note (start)
      final bottom1StartSec = currentTimeSec;
      final bottom1EndSec = bottom1StartSec + noteDurationSec;
      audioNotes.add(ReferenceNote(
        startSec: bottom1StartSec,
        endSec: bottom1EndSec,
        midi: cycleStartMidi,
        lyric: 'Siren',
      ));
      
      // Top note (peak) - starts 1.5s after bottom1 ends
      final topStartSec = bottom1EndSec + noteSpacingSec;
      final topEndSec = topStartSec + noteDurationSec;
      audioNotes.add(ReferenceNote(
        startSec: topStartSec,
        endSec: topEndSec,
        midi: cycleEndMidi,
        lyric: 'Siren',
      ));
      
      // Bottom note (end) - starts 1.5s after top ends
      final bottom2StartSec = topEndSec + noteSpacingSec;
      final bottom2EndSec = bottom2StartSec + noteDurationSec;
      audioNotes.add(ReferenceNote(
        startSec: bottom2StartSec,
        endSec: bottom2EndSec,
        midi: cycleStartMidi,
        lyric: 'Siren',
      ));
      
      // Move to next cycle: start 2s after bottom2 ends
      currentTimeSec = bottom2EndSec + gapBetweenCyclesSec;
    }
    
    // Debug logging
    if (audioNotes.isNotEmpty) {
      final cyclesGenerated = audioNotes.length ~/ 3;
      debugPrint(
          '[SirensBuilder] Generated visualPath: ${visualPoints.length} points, '
          'audioNotes: ${audioNotes.length} notes ($cyclesGenerated cycles), '
          'range=${sirenRangeSemitones} semitones');
      if (audioNotes.length >= 3) {
        final firstCycleNotes = audioNotes.take(3).toList();
        final firstStartMidi = firstCycleNotes[0].midi;
        final firstEndMidi = firstCycleNotes[2].midi;
        final firstTopMidi = firstCycleNotes[1].midi;
        final bottom1ToTopGap = firstCycleNotes[1].startSec - firstCycleNotes[0].endSec;
        final topToBottom2Gap = firstCycleNotes[2].startSec - firstCycleNotes[1].endSec;
        debugPrint(
            '[SirensAudio] Cycle 1: startMidi=$firstStartMidi topMidi=$firstTopMidi endMidi=$firstEndMidi '
            '(${firstStartMidi == firstEndMidi ? "start=end ✓" : "MISMATCH"}) '
            'bottom1@${firstCycleNotes[0].startSec.toStringAsFixed(2)}s, '
            'top@${firstCycleNotes[1].startSec.toStringAsFixed(2)}s (gap=${bottom1ToTopGap.toStringAsFixed(2)}s), '
            'bottom2@${firstCycleNotes[2].startSec.toStringAsFixed(2)}s (gap=${topToBottom2Gap.toStringAsFixed(2)}s)');
        
        // Validate: start and end notes should be the same, gaps should be ~1.5s
        if (firstStartMidi != firstEndMidi) {
          debugPrint(
              '[SirensBuilder] ERROR: Start and end notes don\'t match: '
              'start=$firstStartMidi, end=$firstEndMidi');
        }
        if ((bottom1ToTopGap - noteSpacingSec).abs() > 0.1 || (topToBottom2Gap - noteSpacingSec).abs() > 0.1) {
          debugPrint(
              '[SirensBuilder] WARNING: Note spacing not ~1.5s: '
              'bottom1->top=${bottom1ToTopGap.toStringAsFixed(2)}s, '
              'top->bottom2=${topToBottom2Gap.toStringAsFixed(2)}s');
        }
      }
    }
    
    return SirenExerciseResult(
      visualPath: SirenPath(points: visualPoints),
      audioNotes: audioNotes,
    );
  }

}
