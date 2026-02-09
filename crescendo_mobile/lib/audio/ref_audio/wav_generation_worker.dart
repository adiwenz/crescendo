import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/exercise_plan.dart';
import '../../models/pitch_highway_difficulty.dart';
import '../../models/vocal_exercise.dart';
import '../../services/exercise_plan_builder.dart';
import '../../services/review_audio_bounce_service.dart';
import '../../utils/audio_constants.dart';
import 'ref_spec.dart';

class WavGenerationInput {
  final RefSpec spec;
  final VocalExercise exercise;
  final String tempOutputPath;

  WavGenerationInput({
    required this.spec,
    required this.exercise,
    required this.tempOutputPath,
  });
}

class WavGenerationOutput {
  final ExercisePlan plan;
  final bool success;
  final String? errorMessage;

  WavGenerationOutput({
    required this.plan,
    this.success = true,
    this.errorMessage,
  });
}

/// Worker that runs in an isolate to generate WAV files.
class WavGenerationWorker {
  
  /// Entry point for the compute function.
  static Future<WavGenerationOutput> generate(WavGenerationInput input) async {
    try {
      final spec = input.spec;
      final exercise = input.exercise;
      
      // 1. Build the metadata (TransposedExerciseBuilder)
      // This calculates the notes based on the difficulty and range in the spec
      final internalPlan = await ExercisePlanBuilder.buildMetadata(
        exercise: exercise,
        lowestMidi: spec.lowMidi,
        highestMidi: spec.highMidi,
        difficulty: PitchHighwayDifficulty.values.firstWhere(
            (d) => d.name == (spec.extraOptions['difficulty'] as String? ?? 'beginner')),
        wavFilePath: input.tempOutputPath,
      );
      
      // 2. Synthesize audio
      // Using ReviewAudioBounceService to render 16-bit PCM WAV
      final bounceService = ReviewAudioBounceService();
      await bounceService.renderReferenceWav(
        notes: internalPlan.notes,
        durationSec: internalPlan.durationSec,
        sampleRate: spec.sampleRate.toInt(),
        savePath: input.tempOutputPath,
      );
      
      // 3. Shift visual notes to account for the sync chirp offset
      // This is crucial for UI alignment
      final offset = AudioConstants.totalChirpOffsetSec;
      final shiftedNotes = internalPlan.notes.map((n) {
        return n.copyWith(
          startSec: n.startSec + offset,
          endSec: n.endSec + offset,
        );
      }).toList();
      
      final finalPlan = internalPlan.copyWith(
        notes: shiftedNotes,
        durationSec: internalPlan.durationSec + offset,
      );

      return WavGenerationOutput(plan: finalPlan);

    } catch (e, stack) {
      debugPrint('[WavWorker] Error generating ${input.spec.filename}: $e');
      return WavGenerationOutput(
        plan: ExercisePlan.empty(), // Dummy
        success: false,
        errorMessage: e.toString(),
      );
    }
  }
}
