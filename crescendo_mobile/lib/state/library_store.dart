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
  static const _bestScoresKey = 'best_scores';
  static const _lastCompletedKey = 'last_completed';
  static const _lastScoresKey = 'last_scores';
  static const _timesCompletedKey = 'times_completed';
  final Map<String, int> _bestScores = {};
  final Map<String, int> _lastScores = {};
  final Map<String, DateTime> _lastCompletedAt = {};
  final Map<String, int> _timesCompleted = {};

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
  Map<String, int> get bestScores => Map.unmodifiable(_bestScores);
  Map<String, int> get lastScores => Map.unmodifiable(_lastScores);
  Map<String, DateTime> get lastCompletedAt => Map.unmodifiable(_lastCompletedAt);
  Map<String, int> get timesCompleted => Map.unmodifiable(_timesCompleted);

  void markCompleted(String exerciseId, {int? score}) {
    _completed.add(exerciseId);
    if (score != null) {
      final current = _bestScores[exerciseId] ?? 0;
      if (score > current) _bestScores[exerciseId] = score;
      _lastScores[exerciseId] = score;
    }
    _timesCompleted[exerciseId] = (_timesCompleted[exerciseId] ?? 0) + 1;
    _lastCompletedAt[exerciseId] = DateTime.now();
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
    }
    final best = prefs.getStringList(_bestScoresKey);
    if (best != null) {
      _bestScores
        ..clear()
        ..addAll(best.fold<Map<String, int>>({}, (map, entry) {
          final parts = entry.split(':');
          if (parts.length == 2) {
            final id = parts[0];
            final val = int.tryParse(parts[1]);
            if (val != null) map[id] = val;
          }
          return map;
        }));
    }
    final last = prefs.getStringList(_lastCompletedKey);
    if (last != null) {
      _lastCompletedAt
        ..clear()
        ..addAll(last.fold<Map<String, DateTime>>({}, (map, entry) {
          final idx = entry.indexOf(':');
          if (idx > 0) {
            final id = entry.substring(0, idx);
            final ts = entry.substring(idx + 1);
            final dt = DateTime.tryParse(ts);
            if (dt != null) map[id] = dt;
          }
          return map;
        }));
    }
    final lastScores = prefs.getStringList(_lastScoresKey);
    if (lastScores != null) {
      _lastScores
        ..clear()
        ..addAll(lastScores.fold<Map<String, int>>({}, (map, entry) {
          final parts = entry.split(':');
          if (parts.length == 2) {
            final id = parts[0];
            final val = int.tryParse(parts[1]);
            if (val != null) map[id] = val;
          }
          return map;
        }));
    }
    final times = prefs.getStringList(_timesCompletedKey);
    if (times != null) {
      _timesCompleted
        ..clear()
        ..addAll(times.fold<Map<String, int>>({}, (map, entry) {
          final parts = entry.split(':');
          if (parts.length == 2) {
            final id = parts[0];
            final val = int.tryParse(parts[1]);
            if (val != null) map[id] = val;
          }
          return map;
        }));
    }
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_completedKey, _completed.toList());
    await prefs.setStringList(
      _bestScoresKey,
      _bestScores.entries.map((e) => '${e.key}:${e.value}').toList(),
    );
    await prefs.setStringList(
      _lastCompletedKey,
      _lastCompletedAt.entries.map((e) => '${e.key}:${e.value.toIso8601String()}').toList(),
    );
    await prefs.setStringList(
      _lastScoresKey,
      _lastScores.entries.map((e) => '${e.key}:${e.value}').toList(),
    );
    await prefs.setStringList(
      _timesCompletedKey,
      _timesCompleted.entries.map((e) => '${e.key}:${e.value}').toList(),
    );
  }

  Future<void> reset() async {
    _completed.clear();
    _bestScores.clear();
    _lastScores.clear();
    _lastCompletedAt.clear();
    _timesCompleted.clear();
    notifyListeners();
    await save();
  }
}

/// Global instance you can reuse across the app.
final LibraryStore libraryStore = LibraryStore();
