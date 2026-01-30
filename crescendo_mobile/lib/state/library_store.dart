import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/seed_library.dart';
import '../models/category.dart';
import '../models/exercise.dart';
import '../services/attempt_repository.dart';
import '../utils/daily_completion_utils.dart';

class LibraryStore extends ChangeNotifier {
  final List<Category> _categories = seedLibraryCategories();
  final Map<String, List<Exercise>> _exercises = {};
  final Map<String, Set<String>> _completedByDate = {}; // dateKey -> exerciseIds
  static const _completedTodayKeyPrefix = 'completed_today_v2';
  static const _completedKey = 'completed_exercises'; // Keep for historical stats
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

  /// Returns exercise IDs that earned daily effort credit TODAY only (date-scoped).
  /// Source of truth: DB sessions with countedForDailyEffort; synced on load and when attempts persist.
  Set<String> get completedExerciseIds {
    final today = DailyCompletionUtils.getTodayDateKey();
    return Set.unmodifiable(_completedByDate[today] ?? {});
  }

  Map<String, int> get bestScores => Map.unmodifiable(_bestScores);
  Map<String, int> get lastScores => Map.unmodifiable(_lastScores);
  Map<String, DateTime> get lastCompletedAt => Map.unmodifiable(_lastCompletedAt);
  Map<String, int> get timesCompleted => Map.unmodifiable(_timesCompleted);

  /// Mark an exercise as completed for TODAY (daily effort credit)
  void markCompletedToday(String exerciseId, {int? score}) {
    final today = DailyCompletionUtils.getTodayDateKey();
    _completedByDate.putIfAbsent(today, () => {}).add(exerciseId);
    
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

  /// Legacy method - redirects to markCompletedToday
  void markCompleted(String exerciseId, {int? score}) {
    markCompletedToday(exerciseId, score: score);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DailyCompletionUtils.getTodayDateKey();

    // Source of truth for daily checklist: DB sessions with countedForDailyEffort for today
    await AttemptRepository.instance.ensureLoaded();
    final creditedToday = await AttemptRepository.instance.getTodayCompletedExercises();
    _completedByDate[today] = creditedToday;

    // Fallback: also apply any from prefs (e.g. same-session before DB write)
    final savedToday = prefs.getStringList('$_completedTodayKeyPrefix:$today');
    if (savedToday != null) {
      _completedByDate[today] = Set.from(_completedByDate[today] ?? {})..addAll(savedToday);
    }
    
    // Load best scores
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
    final today = DailyCompletionUtils.getTodayDateKey();
    
    // Save today's completions
    final todayCompleted = _completedByDate[today]?.toList() ?? [];
    await prefs.setStringList('$_completedTodayKeyPrefix:$today', todayCompleted);
    
    // Save other stats
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
    _completedByDate.clear();
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
