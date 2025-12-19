import 'package:flutter/material.dart';

import '../models/pitch_highway_difficulty.dart';
import '../services/exercise_repository.dart';
import '../ui/screens/exercise_player_screen.dart';
import '../models/vocal_exercise.dart';

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
          pitchDifficulty: PitchHighwayDifficulty.medium,
        ),
      ),
  };

  static ExerciseRouteEntry? entryFor(String exerciseId) => _entries[exerciseId];

  static List<ExerciseRouteEntry> entriesForCategory(String categoryId) =>
      _entries.values.where((e) => e.categoryId == categoryId).toList();

  static bool open(BuildContext context, String exerciseId) {
    final entry = entryFor(exerciseId);
    if (entry == null) return false;
    Navigator.push(context, MaterialPageRoute(builder: entry.builder));
    return true;
  }
}
