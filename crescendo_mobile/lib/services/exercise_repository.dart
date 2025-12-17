import '../data/exercise_seed.dart';
import '../models/exercise_category.dart';
import '../models/vocal_exercise.dart';

class ExerciseRepository {
  List<ExerciseCategory> getCategories() {
    final categories = List<ExerciseCategory>.from(seedExerciseCategories());
    categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return categories;
  }

  List<VocalExercise> getExercises() {
    return List<VocalExercise>.from(seedVocalExercises());
  }

  List<VocalExercise> getExercisesForCategory(String categoryId) {
    return getExercises().where((e) => e.categoryId == categoryId).toList();
  }

  ExerciseCategory getCategory(String categoryId) {
    return getCategories().firstWhere((c) => c.id == categoryId);
  }

  VocalExercise getExercise(String exerciseId) {
    return getExercises().firstWhere((e) => e.id == exerciseId);
  }
}
