import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/seed_library.dart';
import '../models/category.dart';
import '../models/exercise.dart';

class LibraryStore extends ChangeNotifier {
  final List<Category> _categories = seedLibraryCategories();
  final Map<String, List<Exercise>> _exercises = {};
  final Set<String> _completed = <String>{};
  static const _completedKey = 'completed_exercises';

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
    save();
    notifyListeners();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_completedKey);
    if (saved != null) {
      _completed
        ..clear()
        ..addAll(saved);
      notifyListeners();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_completedKey, _completed.toList());
  }

  Future<void> reset() async {
    _completed.clear();
    notifyListeners();
    await save();
  }
}

/// Global instance you can reuse across the app.
final LibraryStore libraryStore = LibraryStore();
