import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../models/pitch_highway_difficulty.dart';
import '../models/pitch_segment.dart';
import '../models/reference_note.dart';
import '../models/siren_exercise_result.dart';
import '../models/siren_path.dart';
import '../models/vocal_exercise.dart';
import '../utils/pitch_highway_tempo.dart';
import '../utils/audio_constants.dart';
import '../utils/pitch_math.dart';
import 'harmonic_functions.dart';
import '../models/harmonic_models.dart';

/// Builds a complete transposed exercise sequence that starts at the user's lowest note
/// and steps up by semitones until reaching the highest note.
class TransposedExerciseBuilder {
  /// Returns a record containing:
  /// - `melody`: List of reference notes for the vocal melody (seconds-based for UI)
  /// - `harmony`: List of reference notes for the backing harmony (seconds-based for UI)
  /// - `chordEvents`: List of tick-based chord events for audio generation
  /// - `modEvents`: List of tick-based modulation events for audio generation
  static ({
    List<ReferenceNote> melody, 
    List<ReferenceNote> harmony,
    List<TickChordEvent> chordEvents,
    List<TickModulationEvent> modEvents,
    int initialRootMidi,
  }) buildTransposedSequence({
    required VocalExercise exercise,
    required int lowestMidi,
    required int highestMidi,
    double? leadInSec,
    PitchHighwayDifficulty? difficulty,
  }) {
    // 1. Constrain range based on register (Chest/Head)
    final constrained = _constrainRange(
      exercise: exercise,
      userLowest: lowestMidi,
      userHighest: highestMidi,
    );
    final effectiveLowest = constrained.$1;
    var effectiveHighest = constrained.$2;
    final registerType = constrained.$3;

    // 2. Validate range
    if (effectiveLowest > effectiveHighest) {
       debugPrint('[TransposedExerciseBuilder] INVALID RANGE: effectiveLowest($effectiveLowest) > effectiveHighest($effectiveHighest). Register=$registerType');
       return (melody: const [], harmony: const [], chordEvents: const [], modEvents: const [], initialRootMidi: 60);
    }

    // Use shared constant if leadInSec not provided
    final effectiveLeadInSec = leadInSec ?? AudioConstants.leadInSec;
    final spec = exercise.highwaySpec;
    if (spec == null || spec.segments.isEmpty) {
      return (melody: <ReferenceNote>[], harmony: <ReferenceNote>[], chordEvents: <TickChordEvent>[], modEvents: <TickModulationEvent>[], initialRootMidi: 60);
    }

    // Special handling for Sirens (Legacy logic preserved for now, empty events)
    if (exercise.id == 'sirens') {
      final sirenResult = buildSirensWithVisualPath(
        exercise: exercise,
        lowestMidi: effectiveLowest,  // Pass constrained range
        highestMidi: effectiveHighest, 
        leadInSec: effectiveLeadInSec,
        difficulty: difficulty,
        skipConstraintHelper: true, // Avoid double constraining
      );
      _validateGeneratedNotes(
         notes: sirenResult.audioNotes,
         exerciseId: exercise.id,
         registerType: registerType,
         allowedMin: effectiveLowest,
         allowedMax: effectiveHighest,
         userMin: lowestMidi,
         userMax: highestMidi,
      );
      return (melody: sirenResult.audioNotes, harmony: <ReferenceNote>[], chordEvents: <TickChordEvent>[], modEvents: <TickModulationEvent>[], initialRootMidi: effectiveLowest);
    }

    // Apply tempo scaling if difficulty is provided
    final multiplier = difficulty != null
        ? PitchHighwayTempo.multiplierFor(difficulty, spec.segments)
        : 1.0;
    final scaledSegmentsRaw = difficulty != null
        ? PitchHighwayTempo.scaleSegments(spec.segments, multiplier)
        : spec.segments;

    // CRITICAL: Sort segments by startMs to ensure chronological order
    final scaledSegments = List<PitchSegment>.from(scaledSegmentsRaw)
      ..sort((a, b) => a.startMs.compareTo(b.startMs));

    // CRITICAL: Anchor to the LOWEST note in the pattern
    final firstEvent = scaledSegments.first;
    // ... (Range calculation logic same as before)
    final firstEventMidi = firstEvent.midiNote;
    final baseRootMidi = firstEventMidi;
    
    final patternOffsets = _extractPatternOffsets(scaledSegments, baseRootMidi);
    if (patternOffsets.isEmpty) return (melody: <ReferenceNote>[], harmony: <ReferenceNote>[], chordEvents: <TickChordEvent>[], modEvents: <TickModulationEvent>[], initialRootMidi: 60);

    final patternMin = patternOffsets.reduce(math.min);
    final patternMax = patternOffsets.reduce(math.max);
    final patternSpan = patternMax - patternMin;

    const startPaddingSemitones = 0;
    var upperBound = effectiveHighest - patternSpan;
    if (upperBound < effectiveLowest) {
      debugPrint('[TransposedExerciseBuilder] Warning: Range too small. Clamping.');
      upperBound = effectiveLowest;
      effectiveHighest = math.max(effectiveHighest, effectiveLowest + patternSpan);
    }

    final startTargetMidi = (effectiveLowest + startPaddingSemitones)
        .clamp(effectiveLowest, upperBound);
    final firstRootMidi = startTargetMidi - patternMin;
    
    // --- MUSICAL CLOCK SETUP ---
    // Standardize on 120 BPM for predictable timing
    const bpm = 120;
    const timeSigTop = 4;
    const sampleRate = AudioConstants.audioSampleRate;
    const clock = MusicalClock(bpm: bpm, timeSignatureTop: timeSigTop, sampleRate: sampleRate);

    // Calculate pattern duration in ticks
    final patternDurationMs = scaledSegments.isEmpty
        ? 0
        : scaledSegments.map((s) => s.endMs).reduce(math.max);
    final patternDurationTicks = clock.secondsToTicks(patternDurationMs / 1000.0);
    
    // Gap: 4 beats at 120 BPM = 2.0 seconds = 1920 ticks (at 480 PPQ)
    final gapTicks = clock.secondsToTicks(2.0); 

    // Build all transposed repetitions
    final allNotes = <ReferenceNote>[];
    final allHarmony = <ReferenceNote>[];
    final allChordEvents = <TickChordEvent>[];
    final allModEvents = <TickModulationEvent>[];

    var transpositionSemitones = 0;
    // Start ticks: convert leadInSec to ticks
    var currentTick = clock.secondsToTicks(effectiveLeadInSec);

    while (true) {
      final rootMidi = firstRootMidi + transpositionSemitones;
      final segmentLow = rootMidi + patternMin;
      final segmentHigh = rootMidi + patternMax;

      if (segmentHigh > effectiveHighest) break;
      if (segmentLow < effectiveLowest) {
        transpositionSemitones++;
        continue;
      }

      // 1. Schedule Melody Notes
      final repetitionNotes = _buildNotesForTransposition(
        segments: scaledSegments,
        baseRootMidi: baseRootMidi,
        rootMidi: rootMidi,
        startTimeSec: clock.ticksToSeconds(currentTick),
        exerciseId: exercise.id,
      );
      allNotes.addAll(repetitionNotes);

      // 2. Schedule Harmony (Exercise Progression)
      if (exercise.chordProgression != null && exercise.chordProgression!.isNotEmpty) {
        for (final event in exercise.chordProgression!) {
          final eventStartTick = currentTick + clock.secondsToTicks(event.startMs / 1000.0);
          final eventDurTicks = clock.secondsToTicks(event.durationMs / 1000.0);
          
          // Add Tick Event
          allChordEvents.add(TickChordEvent(
            startTick: eventStartTick,
            durationTicks: eventDurTicks,
            chord: event.chord,
            octaveOffset: -1,
          ));

          // Add UI Reference Notes
          final chordMidis = HarmonicFunctions.getChordNotes(
            chord: event.chord,
            keyRootMidi: rootMidi,
            isMinorKey: false,
            octaveOffset: -1,
          );
          for (final midi in chordMidis) {
            allHarmony.add(ReferenceNote(
              startSec: clock.ticksToSeconds(eventStartTick),
              endSec: clock.ticksToSeconds(eventStartTick + eventDurTicks),
              midi: midi,
            ));
          }
        }
      }
      
      // 3. Modulation Chords (Gap Filling)
      final nextRootMidi = rootMidi + 1; 
      final nextHigh = nextRootMidi + patternMax;
      
      if (nextHigh <= effectiveHighest) {
        final gapStartTick = currentTick + patternDurationTicks;
        
        // Timing Logic (4 Beats Total Gap):
        // Beat 1: Silence (Wait)
        // Beat 2: Chord 1 (Current Key) - Duration 1 beat
        // Beat 3: Chord 2 (Target Key) - Duration 1.5 beats (dotted quarter)
        // Beat 4 (second half): Silence
        
        const ticksPerBeat = MusicalClock.ppq; // 480
        
        // Chord 1
        final chord1StartTick = gapStartTick + ticksPerBeat; // Start at Beat 2
        final chord1DurTicks = ticksPerBeat; // 1 beat duration
        
        // Add Chord 1 Event
        allChordEvents.add(TickChordEvent(
          startTick: chord1StartTick,
          durationTicks: chord1DurTicks,
          chord: Chord.I_Major,
          octaveOffset: 0,
        ));
        
        // Add Chord 1 UI Notes
        final chord1Notes = HarmonicFunctions.getChordNotes(
          chord: Chord.I_Major,
          keyRootMidi: rootMidi,
          isMinorKey: false,
          octaveOffset: 0,
        );
        for (final midi in chord1Notes) {
          allHarmony.add(ReferenceNote(
            startSec: clock.ticksToSeconds(chord1StartTick),
            endSec: clock.ticksToSeconds(chord1StartTick + chord1DurTicks),
            midi: midi,
          ));
        }

        // Chord 2
        final chord2StartTick = gapStartTick + (ticksPerBeat * 2); // Start at Beat 3
        final chord2DurTicks = (ticksPerBeat * 1.5).round(); // 1.5 beats (dotted quarter)
        
        // Add Chord 2 Event
        allChordEvents.add(TickChordEvent(
          startTick: chord2StartTick,
          durationTicks: chord2DurTicks,
          chord: Chord.I_Major,
          octaveOffset: 0,
        ));

        // Add Chord 2 UI Notes
        final chord2Notes = HarmonicFunctions.getChordNotes(
          chord: Chord.I_Major,
          keyRootMidi: nextRootMidi,
          isMinorKey: false,
          octaveOffset: 0,
        );
        for (final midi in chord2Notes) {
          allHarmony.add(ReferenceNote(
            startSec: clock.ticksToSeconds(chord2StartTick),
            endSec: clock.ticksToSeconds(chord2StartTick + chord2DurTicks),
            midi: midi,
          ));
        }
        
        // Schedule Modulation Event at the very end of the gap (beginning of next pattern)
        final nextPatternStartTick = currentTick + patternDurationTicks + gapTicks;
        allModEvents.add(TickModulationEvent(
          tick: nextPatternStartTick, 
          semitoneDelta: 1,
        ));
      }

      // Update time for next repetition
      currentTick += patternDurationTicks + gapTicks;
      transpositionSemitones++;
      if (transpositionSemitones > 100) break;
    }

    // ... (Validation logic removed for brevity, will rely on visual/audio checks)
    _validateGeneratedNotes(
         notes: allNotes,
         exerciseId: exercise.id,
         registerType: registerType,
         allowedMin: effectiveLowest,
         allowedMax: effectiveHighest,
         userMin: lowestMidi,
         userMax: highestMidi,
      );

    return (
      melody: allNotes, 
      harmony: allHarmony, 
      chordEvents: allChordEvents, 
      modEvents: allModEvents,
      initialRootMidi: firstRootMidi,
    );
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
    bool skipConstraintHelper = false,
  }) {
    // 1. Constrain range if not already done
    final int effectiveLowest;
    final int effectiveHighest;
    final String registerType;
    
    if (!skipConstraintHelper) {
      final constrained = _constrainRange(
        exercise: exercise,
        userLowest: lowestMidi,
        userHighest: highestMidi,
      );
      effectiveLowest = constrained.$1;
      effectiveHighest = constrained.$2;
      registerType = constrained.$3;
    } else {
      effectiveLowest = lowestMidi;
      effectiveHighest = highestMidi;
      registerType = 'Pre-Constrained';
    }

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
    final cyclesNeeded = (effectiveHighest - effectiveLowest - sirenRangeSemitones + 1).clamp(1, 100);
    
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
      final cycleStartMidi = effectiveLowest + cycleIndex;
      final cycleEndMidi = cycleStartMidi + sirenRangeSemitones;
      
      // Stop if transposed highest note exceeds highestMidi
      // Stop if transposed highest note exceeds highestMidi
      // EXCEPTION: Allow at least one cycle (index 0) even if range is too small
      if (cycleIndex > 0 && cycleEndMidi > effectiveHighest) break;
      
      // Each cycle: cycleStartMidi -> cycleEndMidi -> cycleStartMidi (bell curve)
      const cycleRange = sirenRangeSemitones;
      
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
    
    _validateGeneratedNotes(
         notes: audioNotes,
         exerciseId: exercise.id,
         registerType: registerType,
         allowedMin: effectiveLowest,
         allowedMax: effectiveHighest,
         userMin: lowestMidi,
         userMax: highestMidi,
      );

    return SirenExerciseResult(
      visualPath: SirenPath(points: visualPoints),
      audioNotes: audioNotes,
    );
  }

  // --- Helpers ---

  static (int, int, String) _constrainRange({
    required VocalExercise exercise,
    required int userLowest,
    required int userHighest,
  }) {
    final rangeSpan = userHighest - userLowest;
    final midpointMidi = userLowest + (rangeSpan / 2).floor();
    
    if (exercise.tags.contains('chest')) {
      // Chest: [lowest, midpoint]
      return (userLowest, midpointMidi, 'Chest');
    } else if (exercise.tags.contains('head')) {
      // Head: [midpoint + 1, highest]
      return (midpointMidi + 1, userHighest, 'Head');
    } else {
      // Full range (mix/default)
      return (userLowest, userHighest, 'Full');
    }
  }

  static void _validateGeneratedNotes({
    required List<ReferenceNote> notes,
    required String exerciseId,
    required String registerType,
    required int allowedMin,
    required int allowedMax,
    required int userMin,
    required int userMax,
  }) {
    if (!kDebugMode) return;
    
    if (notes.isEmpty) {
      debugPrint('[TransposedExerciseBuilder] VALIDATION: No notes generated for $exerciseId ($registerType). Range too small?');
      return;
    }

    final minNote = notes.map((n) => n.midi.round()).reduce(math.min);
    final maxNote = notes.map((n) => n.midi.round()).reduce(math.max);
    
    // midpoint for logging context
    final rangeSpan = userMax - userMin;
    final midpoint = userMin + (rangeSpan / 2).floor();

    debugPrint(
      '[TransposedExerciseBuilder] VALIDATION for $exerciseId:\n'
      '  Register: $registerType\n'
      '  User Range: $userMin - $userMax (mid=$midpoint)\n'
      '  Allowed Range: $allowedMin - $allowedMax\n'
      '  Generated Range: $minNote - $maxNote\n'
      '  Notes Count: ${notes.length}'
    );

    if (minNote < allowedMin) {
      debugPrint('[TransposedExerciseBuilder] WARNING: Min note ($minNote) < Allowed Min ($allowedMin)');
    }
    if (maxNote > allowedMax) {
      debugPrint('[TransposedExerciseBuilder] WARNING: Max note ($maxNote) > Allowed Max ($allowedMax)');
    }
  }
}
