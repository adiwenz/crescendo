import '../data/exercise_seed.dart';
import '../models/exercise_category.dart';
import '../models/vocal_exercise.dart';

class ExerciseRepository {
  static List<VocalExercise>? _cachedExercises;
  static List<ExerciseCategory>? _cachedCategories;

  // Singleton instance
  ExerciseRepository._private();
  static final ExerciseRepository instance = ExerciseRepository._private();
  
  // Factory for easy access (optional, but good for backward compat if needed, 
  // though we will migrate calls to .instance or dependency injection style)
  factory ExerciseRepository() => instance;

  List<ExerciseCategory> getCategories() {
    if (_cachedCategories != null) return _cachedCategories!;
    final categories = List<ExerciseCategory>.from(seedExerciseCategories());
    categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    _cachedCategories = categories;
    return categories;
  }

  List<VocalExercise> getExercises() {
    _cachedExercises ??= List<VocalExercise>.from(seedVocalExercises());
    return _cachedExercises!;
  }

  List<VocalExercise> getExercisesForCategory(String categoryId) {
    return getExercises().where((e) => e.categoryId == categoryId).toList();
  }

  ExerciseCategory getCategory(String categoryId) {
    return getCategories().firstWhere(
      (c) => c.id == categoryId,
      orElse: () => getCategories().first, // Fallback to first category if not found
    );
  }

  VocalExercise getExercise(String exerciseId) {
    return getExercises().firstWhere((e) => e.id == exerciseId);
  }

}
