import 'package:flutter/material.dart';

import '../../models/pitch_highway_difficulty.dart';
import '../../models/vocal_exercise.dart';
import 'exercise_player_screen.dart';

Widget buildExerciseScreen(
  VocalExercise exercise, {
  PitchHighwayDifficulty? pitchDifficulty,
}) {
  switch (exercise.type) {
    case ExerciseType.pitchHighway:
    case ExerciseType.breathTimer:
    case ExerciseType.sovtTimer:
    case ExerciseType.sustainedPitchHold:
    case ExerciseType.pitchMatchListening:
    case ExerciseType.articulationRhythm:
    case ExerciseType.dynamicsRamp:
    case ExerciseType.cooldownRecovery:
      return ExercisePlayerScreen(
        exercise: exercise,
        pitchDifficulty: pitchDifficulty,
      );
  }
}
