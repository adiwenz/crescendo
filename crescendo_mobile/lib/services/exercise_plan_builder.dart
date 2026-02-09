import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/exercise_plan.dart';
import '../models/vocal_exercise.dart';
import '../models/pitch_highway_difficulty.dart';
import 'transposed_exercise_builder.dart';
import '../utils/audio_constants.dart';
import '../utils/pitch_math.dart';

/// Orchestrator for building a complete [ExercisePlan] for a given [VocalExercise].
class ExercisePlanBuilder {
  
  /// Builds the metadata and note timeline for an exercise plan.
  /// Does NOT perform the actual synthesis (handled by ReferenceAudioGenerator).
  static Future<ExercisePlan> buildMetadata({
    required VocalExercise exercise,
    required int lowestMidi,
    required int highestMidi,
    required PitchHighwayDifficulty difficulty,
    required String wavFilePath, // Path where audio will be synthesized
  }) async {
    
    // 1. Build the transposed sequence (Visuals + Audio markers)
    final sequence = TransposedExerciseBuilder.buildTransposedSequence(
      exercise: exercise,
      lowestMidi: lowestMidi,
      highestMidi: highestMidi,
      difficulty: difficulty,
      leadInSec: AudioConstants.leadInSec,
    );
    final notes = sequence.melody;
    final harmonyNotes = sequence.harmony;
    final chordEvents = sequence.chordEvents;
    final modEvents = sequence.modEvents;

    // 2. Calculate duration
    final lastNoteEnd = notes.isEmpty ? 0.0 : notes.map((n) => n.endSec).reduce((a, b) => a > b ? a : b);
    final durationMs = ((lastNoteEnd + 1.0) * 1000).round(); // 1s buffer at end

    // 3. Generate hashes for caching
    final rangeHash = _generateRangeHash(lowestMidi, highestMidi);
    final patternHash = generatePatternHash(exercise, difficulty);

    final firstMidi = notes.isEmpty ? 60 : notes.first.midi.round();
    final keyLabel = PitchMath.midiToName(firstMidi);

    return ExercisePlan(
      id: exercise.id,
      title: exercise.name,
      keyLabel: keyLabel,
      wavFilePath: wavFilePath,
      notes: notes,
      harmonyNotes: harmonyNotes,
      chordEvents: chordEvents,
      modEvents: modEvents,
      sampleRate: AudioConstants.audioSampleRate,
      durationMs: durationMs,
      rangeHash: rangeHash,
      patternHash: patternHash,
      leadInSec: AudioConstants.leadInSec,
      initialRootMidi: sequence.initialRootMidi,
    );
  }

  static String _generateRangeHash(int low, int high) {
    return '$low-$high';
  }

  static String generatePatternHash(VocalExercise ex, PitchHighwayDifficulty diff) {
    var raw = '${ex.id}|${diff.name}';
    if (ex.chordProgression != null) {
      raw += '|${ex.chordProgression!.length}'; // Simple hash: length of chords
      // Ideally hashing the content, but length + string rep is better
      raw += '|${ex.chordProgression.toString()}';
    }
    final bytes = utf8.encode(raw);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 8);
  }
}
