import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;

import '../models/pitch_highway_difficulty.dart';
import '../models/pitch_segment.dart';
import '../models/reference_note.dart';
import '../models/siren_exercise_result.dart';
import '../models/siren_path.dart';
import '../models/vocal_exercise.dart';
import '../utils/pitch_highway_tempo.dart';
import '../utils/audio_constants.dart';
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
    final effectiveLeadInSec = leadInSec ?? AudioConstants.leadInSec;
    final spec = exercise.highwaySpec;
    if (spec == null || spec.segments.isEmpty) return const [];

    // Apply tempo scaling if difficulty is provided
    final multiplier = difficulty != null
        ? PitchHighwayTempo.multiplierFor(difficulty, spec.segments)
        : 1.0;
    final scaledSegmentsRaw = difficulty != null
        ? PitchHighwayTempo.scaleSegments(spec.segments, multiplier)
        : spec.segments;

    // CRITICAL: Sort segments by startMs to ensure chronological order
    // This guarantees that segments[i] corresponds to the i-th chronological event
    final scaledSegments = List<PitchSegment>.from(scaledSegmentsRaw)
      ..sort((a, b) => a.startMs.compareTo(b.startMs));

    // CRITICAL: Anchor to the LOWEST note in the pattern (patternMin), not the first chronological note
    // For descending runs: first chronological note is HIGHEST, last is LOWEST
    // We want: lowest note = startTargetMidi (B2), first chronological note = startTargetMidi + patternSpan (B3)
    
    // Extract pattern offsets relative to the first chronological event
    final firstEvent = scaledSegments.first;
    final firstEventMidi = firstEvent.midiNote;
    final baseRootMidi = firstEventMidi; // Use first chronological event as base for offset calculation
    
    final patternOffsets = _extractPatternOffsets(scaledSegments, baseRootMidi);
    if (patternOffsets.isEmpty) return const [];

    // Find the min and max offsets in the pattern
    final patternMin = patternOffsets.reduce(math.min); // Lowest note offset (e.g., -12)
    final patternMax = patternOffsets.reduce(math.max); // Highest note offset (e.g., 0)
    final patternSpan = patternMax - patternMin; // Total span (e.g., 12 semitones)

    // Calculate a safe start target MIDI near the bottom of the user range
    // This is the LOWEST note we want in the pattern
    const startPaddingSemitones = 0;
    final startTargetMidi = (lowestMidi + startPaddingSemitones)
        .clamp(lowestMidi, highestMidi - patternSpan);

    // ENFORCE INVARIANT: rootMidi anchors the LOWEST note (patternMin) to startTargetMidi
    // Formula: lowestNote = rootMidi + patternMin = startTargetMidi
    // Therefore: rootMidi = startTargetMidi - patternMin
    // For descending runs: patternMin = -12, so rootMidi = startTargetMidi - (-12) = startTargetMidi + 12
    // First chronological note: rootMidi + patternMax = (startTargetMidi + 12) + 0 = startTargetMidi + 12 ✓
    // Lowest note: rootMidi + patternMin = (startTargetMidi + 12) + (-12) = startTargetMidi ✓
    final firstRootMidi = startTargetMidi - patternMin;
    
    // Verify segments are sorted (sanity check)
    for (var i = 1; i < scaledSegments.length; i++) {
      assert(
        scaledSegments[i - 1].startMs <= scaledSegments[i].startMs,
        'Segments must be sorted by startMs in chronological order. '
        'Segment ${i - 1} has startMs=${scaledSegments[i - 1].startMs}, '
        'segment $i has startMs=${scaledSegments[i].startMs}',
      );
    }
    
    // Debug logs removed to reduce noise on app restart
    
    // Special handling for Sirens: generate visual path + minimal audio notes
    // Note: For Sirens, we need to return a different structure, but for now
    // we'll keep the same return type and handle it in the caller
    // TODO: Refactor to return SirenExerciseResult for Sirens
    if (exercise.id == 'sirens') {
      final sirenResult = buildSirensWithVisualPath(
        exercise: exercise,
        lowestMidi: lowestMidi,
        highestMidi: highestMidi,
        leadInSec: effectiveLeadInSec,
        difficulty: difficulty,
      );
      return sirenResult.audioNotes;
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

    // Debug logs removed to reduce noise on app restart

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

      // Build notes for this root using pattern offsets
      // targetMidi = rootMidi + patternOffset (where patternOffset = seg.midiNote - baseRootMidi)
      final repetitionNotes = _buildNotesForTransposition(
        segments: scaledSegments,
        baseRootMidi: baseRootMidi,
        rootMidi: rootMidi,
        startTimeSec: currentTimeSec,
        exerciseId: exercise.id,
      );
      
      allNotes.addAll(repetitionNotes);
      
      // Debug logs removed to reduce noise on app restart
      
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
      
      // Find the actual lowest and highest notes in the generated sequence
      final allMidis = allNotes.map((n) => n.midi.round()).toList();
      final actualLowestMidi = allMidis.reduce((a, b) => a < b ? a : b);
      
      // Debug logs removed to reduce noise on app restart
      
      // ENFORCE INVARIANT: The LOWEST note in the pattern MUST equal startTargetMidi
      // This works for both ascending (first chronological = lowest) and descending (first chronological = highest) patterns
      // Expected lowest note = rootMidi + patternMin = startTargetMidi - patternMin + patternMin = startTargetMidi
      final expectedLowestMidi = startTargetMidi;
      final expectedLowestName = PitchMath.midiToName(expectedLowestMidi);
      final lowestDiff = (actualLowestMidi - expectedLowestMidi).abs();
      
      assert(
        actualLowestMidi == expectedLowestMidi,
        'Pattern root misaligned: expected lowest note = $expectedLowestMidi ($expectedLowestName), '
        'but got $actualLowestMidi (${PitchMath.midiToName(actualLowestMidi)}). '
        'Difference: ${lowestDiff} semitones. '
        'Expected: rootMidi = startTargetMidi - patternMin = $startTargetMidi - $patternMin = $firstRootMidi. '
        'Lowest note = rootMidi + patternMin = $firstRootMidi + $patternMin = $expectedLowestMidi. '
        'First chronological note = $firstTargetMidi (may be lowest or highest depending on pattern direction).',
      );
    } else {
      // If no notes were generated, check if it's due to range constraints
      final patternSpan = patternMax - patternMin;
      if (highestMidi - lowestMidi < patternSpan) {
        debugPrint(
            '[TransposedExerciseBuilder] WARNING: User range ($lowestMidi-$highestMidi, span=${highestMidi - lowestMidi}) '
            'is too narrow for pattern span ($patternSpan). No notes generated.');
      }
    }

    return allNotes;
  }


  /// Extracts pattern offsets relative to the base root note, preserving chronological order
  /// Uses only midiNote and endMidi (audio notes), not startMidi (visual glide start)
  /// Returns offsets in the same order as segments appear (for chronological note generation)
  static List<int> _extractPatternOffsets(List<PitchSegment> segments, int baseRootMidi) {
    final offsets = <int>[];
    for (final seg in segments) {
      // Use midiNote (audio note) for pattern offsets
      final offset = seg.midiNote - baseRootMidi;
      if (!offsets.contains(offset)) {
        offsets.add(offset); // Preserve order, avoid duplicates
      }
      // Include endMidi if present (for glides, this is the audio end note)
      if (seg.endMidi != null) {
        final endOffset = seg.endMidi! - baseRootMidi;
        if (!offsets.contains(endOffset)) {
          offsets.add(endOffset);
        }
      }
      // Do NOT include startMidi - it's for visual glides only, not audio transposition
    }
    return offsets;
  }

  /// Builds reference notes for a single transposition of the exercise
  /// 
  /// Uses pattern offsets to compute target MIDI: targetMidi = rootMidi + patternOffset
  /// where patternOffset = seg.midiNote - baseRootMidi
  static List<ReferenceNote> _buildNotesForTransposition({
    required List<PitchSegment> segments,
    required int baseRootMidi,
    required int rootMidi,
    required double startTimeSec,
    String? exerciseId, // Add exercise ID to detect NG Slides and Sirens
  }) {
    final notes = <ReferenceNote>[];
    final isNgSlides = exerciseId == 'ng_slides';
    final isSirens = exerciseId == 'sirens';

    // Process segments in chronological order (they should already be sorted by startMs)
    // The first segment (i == 0) corresponds to the first chronological note event
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      // Segments have absolute times within the pattern (startMs, endMs)
      // Convert to seconds and offset by startTimeSec
      final segStartSec = startTimeSec + (seg.startMs / 1000.0);
      final segEndSec = startTimeSec + (seg.endMs / 1000.0);
      
      // Compute pattern offset: how many semitones this segment is from the first chronological event
      // baseRootMidi = firstEventMidi, so the first segment (i == 0) will have offset = 0
      final patternOffset = seg.midiNote - baseRootMidi;
      
      // Compute target MIDI: rootMidi + patternOffset
      // rootMidi = startTargetMidi - firstEventOffset = startTargetMidi - 0 = startTargetMidi
      // For the first chronological segment (i == 0): patternOffset = 0, so targetMidi = startTargetMidi ✓
      final targetMidi = rootMidi + patternOffset;
      
      // Verify the first chronological segment has offset 0 (sanity check)
      if (i == 0) {
        assert(
          patternOffset == 0,
          'First chronological segment must have offset 0. '
          'seg.midiNote=${seg.midiNote}, baseRootMidi=$baseRootMidi, patternOffset=$patternOffset',
        );
      }
      
      if (seg.isGlide) {
        // Compute endMidi from pattern offset
        final endPatternOffset = (seg.endMidi ?? seg.midiNote) - baseRootMidi;
        final endMidi = rootMidi + endPatternOffset;
        
        // 1. Start anchor (Bottom note)
        notes.add(ReferenceNote(
          startSec: segStartSec,
          endSec: segStartSec + 0.5,
          midi: targetMidi,
          lyric: seg.label,
          isGlideStart: i == 0,
          glideEndMidi: i == 0 ? endMidi : null,
        ));

        // 2. End anchor (Top note)
        notes.add(ReferenceNote(
          startSec: segEndSec - 0.5,
          endSec: segEndSec,
          midi: endMidi,
          lyric: seg.label,
          isGlideEnd: i == segments.length - 1,
        ));
      } else {
        // Regular note: use targetMidi computed from pattern offset
        notes.add(ReferenceNote(
          startSec: segStartSec,
          endSec: segEndSec,
          midi: targetMidi,
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
