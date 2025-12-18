import 'package:flutter/foundation.dart';

import '../data/seed_library.dart';
import '../models/category.dart';
import '../models/exercise.dart';

class LibraryStore extends ChangeNotifier {
  final List<Category> _categories = seedLibraryCategories();
  final Map<String, List<Exercise>> _exercises = {};
  final Set<String> _completed = <String>{};

  LibraryStore() {
    for (final c in _categories) {
      _exercises[c.id] = seedExercisesFor(c.id);
    }
  }

  List<Category> get categories => List.unmodifiable(_categories);

  List<Exercise> exercisesByCategory(String categoryId) {
    return List.unmodifiable(_exercises[categoryId] ?? const []);
  }

  Set<String> get completedExerciseIds => Set.unmodifiable(_completed);

  void markCompleted(String exerciseId) {
    _completed.add(exerciseId);
    notifyListeners();
  }
}
