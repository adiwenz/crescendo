import 'package:flutter/material.dart';

import '../debug/debug_flags.dart';
import '../models/exercise_plan.dart';
import '../models/pitch_highway_difficulty.dart';
import '../models/vocal_exercise.dart';
import '../ui/screens/pitch_highway_screen.dart';
import '../services/exercise_repository.dart';
import '../ui/screens/exercise_player_screen.dart';
import '../core/app_config.dart';

class ExerciseRouteEntry {
  final String id;
  final String categoryId;
  final String title;
  final WidgetBuilder builder;

  const ExerciseRouteEntry({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.builder,
  });
}

class ExerciseRouteRegistry {
  ExerciseRouteRegistry._();

  static const List<String> _v0AllowedIds = [
    'sustained_pitch_holds',
    'five_tone_scales',
    'ng_slides',
  ];

  static final ExerciseRepository _repo = ExerciseRepository();
  static final Map<String, ExerciseRouteEntry> _entries = {
    for (final ex in _repo.getExercises())
      ex.id: ExerciseRouteEntry(
        id: ex.id,
        categoryId: ex.categoryId,
        title: ex.name,
        builder: (_) => ExercisePlayerScreen(
          exercise: ex,
        ),
      ),
  };

  static ExerciseRouteEntry? entryFor(String exerciseId) => _entries[exerciseId];

  static List<ExerciseRouteEntry> entriesForCategory(String categoryId) =>
      _entries.values.where((e) => e.categoryId == categoryId).toList();

  static bool open(
    BuildContext context,
    String exerciseId, {
    int? difficultyLevel,
    ExercisePlan? exercisePlan,
    Future<ExercisePlan>? exercisePlanFuture,
  }) {
    if (AppConfig.isV0 && !_v0AllowedIds.contains(exerciseId)) {
      debugPrint('[V0] Blocked navigation to non-V0 exercise: $exerciseId');
      // Optionally show a toast here
      return false;
    }

    final entry = entryFor(exerciseId);
    if (entry == null) return false;
    if (difficultyLevel != null) {
      final exercise = _repo.getExercises().firstWhere(
            (e) => e.id == exerciseId,
            orElse: () => _repo.getExercises().first,
          );
      final pitchDifficulty =
          exercise.type == ExerciseType.pitchHighway
              ? pitchHighwayDifficultyFromLevel(difficultyLevel)
              : null;

      if (exercise.type == ExerciseType.pitchHighway) {
         Navigator.push(
            context,
            MaterialPageRoute(
               builder: (_) => PitchHighwayScreen(
                  exercise: exercise,
                  pitchDifficulty: pitchDifficulty!,
               ),
            ),
         );
         return true;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExercisePlayerScreen(
            exercise: exercise,
          ),
        ),
      );
      return true;
    }
    Navigator.push(context, MaterialPageRoute(builder: entry.builder));
    return true;
  }
}
