import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/exercise.dart';
import '../services/exercise_repository.dart';

/// Service for selecting daily exercises deterministically based on the current date.
class DailyExerciseService {
  static const String _dailyExercisesKey = 'daily_exercises';
  static const String _dailyExercisesDateKey = 'daily_exercises_date';
  static const int _numDailyExercises = 4;

  final ExerciseRepository _exerciseRepo = ExerciseRepository();

  /// Get today's selected exercises. Returns the same exercises for the entire day.
  Future<List<Exercise>> getTodaysExercises() async {
    final today = _getTodayDateString();
    final prefs = await SharedPreferences.getInstance();
    
    // Check if we have exercises for today
    final savedDate = prefs.getString(_dailyExercisesDateKey);
    if (savedDate == today) {
      final savedIds = prefs.getStringList(_dailyExercisesKey);
      if (savedIds != null && savedIds.length == _numDailyExercises) {
        // Return saved exercises for today
        return _getExercisesByIds(savedIds);
      }
    }

    // Generate new exercises for today
    final selected = await _selectDailyExercises();
    await _saveTodaysExercises(prefs, today, selected);
    return selected;
  }

  /// Select N random exercises with variety (avoid all from same category if possible).
  Future<List<Exercise>> _selectDailyExercises() async {
    // Get all exercises from the library
    final allVocalExercises = _exerciseRepo.getExercises();
    final allExercises = allVocalExercises.map((ve) => _vocalExerciseToExercise(ve)).toList();
    
    if (allExercises.length <= _numDailyExercises) {
      return allExercises;
    }

    // Seed random with today's date for deterministic selection
    final today = _getTodayDateString();
    final seed = today.hashCode;
    final random = Random(seed);

    // Group exercises by category
    final byCategory = <String, List<Exercise>>{};
    for (final ex in allExercises) {
      byCategory.putIfAbsent(ex.categoryId, () => []).add(ex);
    }

    final selected = <Exercise>[];
    final usedCategories = <String>{};
    final shuffledCategories = List<String>.from(byCategory.keys)..shuffle(random);

    // Try to pick one from each category first for variety
    for (final categoryId in shuffledCategories) {
      if (selected.length >= _numDailyExercises) break;
      if (usedCategories.contains(categoryId)) continue;
      
      final categoryExercises = byCategory[categoryId]!;
      if (categoryExercises.isNotEmpty) {
        final picked = categoryExercises[random.nextInt(categoryExercises.length)];
        selected.add(picked);
        usedCategories.add(categoryId);
      }
    }

    // Fill remaining slots with any exercises
    if (selected.length < _numDailyExercises) {
      final selectedIds = selected.map((e) => e.id).toSet();
      final remaining = allExercises.where((e) => !selectedIds.contains(e.id)).toList();
      remaining.shuffle(random);
      while (selected.length < _numDailyExercises && remaining.isNotEmpty) {
        selected.add(remaining.removeAt(0));
      }
    }

    return selected.take(_numDailyExercises).toList();
  }

  /// Convert VocalExercise to Exercise model for Home screen display.
  Exercise _vocalExerciseToExercise(dynamic vocalEx) {
    // Use the existing mapping from seed_library.dart
    return Exercise(
      id: vocalEx.id,
      categoryId: vocalEx.categoryId,
      title: vocalEx.name,
      subtitle: vocalEx.description,
      bannerStyleId: vocalEx.categoryId.hashCode % 5,
    );
  }

  /// Get exercises by their IDs.
  List<Exercise> _getExercisesByIds(List<String> ids) {
    final allVocalExercises = _exerciseRepo.getExercises();
    final allExercises = allVocalExercises.map((ve) => _vocalExerciseToExercise(ve)).toList();
    final exerciseMap = {for (var ex in allExercises) ex.id: ex};
    return ids.map((id) => exerciseMap[id]!).whereType<Exercise>().toList();
  }

  /// Save today's exercises to SharedPreferences.
  Future<void> _saveTodaysExercises(
    SharedPreferences prefs,
    String date,
    List<Exercise> exercises,
  ) async {
    await prefs.setString(_dailyExercisesDateKey, date);
    await prefs.setStringList(_dailyExercisesKey, exercises.map((e) => e.id).toList());
  }

  /// Get today's date as YYYY-MM-DD string.
  String _getTodayDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

/// Global instance for easy access.
final dailyExerciseService = DailyExerciseService();
