import 'package:flutter/material.dart';

import '../services/exercise_repository.dart';
import '../ui/screens/exercise_player_screen.dart';
import '../models/vocal_exercise.dart';
import '../models/pitch_highway_difficulty.dart';
import '../models/exercise_plan.dart';

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

  static final ExerciseRepository _repo = ExerciseRepository();
  static final Map<String, ExerciseRouteEntry> _entries = {
    for (final ex in _repo.getExercises())
      ex.id: ExerciseRouteEntry(
        id: ex.id,
        categoryId: ex.categoryId,
        title: ex.name,
        builder: (_) => ExercisePlayerScreen(
          exercise: ex,
          pitchDifficulty: null,
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
  }) {
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
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExercisePlayerScreen(
            exercise: exercise,
            pitchDifficulty: pitchDifficulty,
            exercisePlan: exercisePlan,
          ),
        ),
      );
      return true;
    }
    Navigator.push(context, MaterialPageRoute(builder: entry.builder));
    return true;
  }
}
