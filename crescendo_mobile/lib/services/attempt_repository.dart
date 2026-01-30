import 'package:flutter/foundation.dart';

import '../data/progress_repository.dart';
import '../models/daily_plan.dart';
import '../models/exercise_attempt.dart';
import '../models/exercise_take.dart';
import '../models/exercise_score.dart';
import '../utils/daily_completion_utils.dart';

/// Thin wrapper over ProgressRepository to expose latest attempts.
class AttemptRepository extends ChangeNotifier {
  AttemptRepository._();
  static final AttemptRepository instance = AttemptRepository._();

  final ProgressRepository _repo = ProgressRepository();
  List<ExerciseAttempt> _cache = const [];
  bool _loaded = false;
  int _revision = 0;
  bool _isRefreshing = false;

  List<ExerciseAttempt> get cache => _cache;
  int get revision => _revision;

  Future<List<ExerciseAttempt>> refresh() async {
    // Prevent concurrent refreshes
    if (_isRefreshing) {
      debugPrint('[AttemptRepository] Refresh already in progress, skipping');
      return _cache;
    }
    _isRefreshing = true;
    try {
      final attempts = await _repo.fetchAttemptSummaries();
      _cache = attempts;
      debugPrint('[AttemptRepository] refreshed: ${_cache.length} summaries');
      _loaded = true;
      _revision++;
      notifyListeners();
    } catch (e, st) {
      debugPrint('[AttemptRepository] refresh failed: $e\n$st');
    } finally {
      _isRefreshing = false;
    }
    return _cache;
  }

  Future<void> save(ExerciseAttempt attempt) async {
    await _repo.saveAttempt(attempt);
    _cache = [attempt, ..._cache.where((a) => a.id != attempt.id)];
    _loaded = true;
    _revision++;
    notifyListeners();
  }

  ExerciseAttempt? latestFor(String exerciseId) {
    final list = _cache.where((a) => a.exerciseId == exerciseId).toList();
    if (list.isEmpty) return null;
    list.sort((a, b) {
      DateTime aTime = a.completedAt ?? a.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      DateTime bTime = b.completedAt ?? b.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return list.first;
  }

  List<ExerciseAttempt> recent({int limit = 10}) {
    return _cache.take(limit).toList();
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    if (_isRefreshing) {
      // If a refresh is already in progress, wait for it to finish or just return
      // Since it's a future, we can just return and the caller can await if needed,
      // but simpler to just skip if already loading.
      return;
    }
    try {
      // Use summary fetch to avoid loading huge JSON blobs into memory
      final attempts = await _repo.fetchAttemptSummaries();
      _cache = attempts;
      _loaded = true;
      debugPrint('[AttemptRepository] ensureLoaded: ${_cache.length} summaries');
    } catch (e, st) {
      debugPrint('[AttemptRepository] ensureLoaded failed: $e\n$st');
    }
  }

  /// Fetches a full attempt with all heavy JSON blobs from the database.
  /// Used for detailed review screens.
  Future<ExerciseAttempt?> getFullAttempt(String id) async {
    return _repo.fetchAttempt(id);
  }

  Future<ExerciseTake?> loadLastTake(String exerciseId) async {
    return _repo.fetchLastTake(exerciseId);
  }
  
  /// Fetches the most recent score for an exercise without loading global history.
  Future<ExerciseScore?> fetchLastScore(String exerciseId) async {
    return _repo.fetchLastScore(exerciseId);
  }

  /// Get completed exercise IDs for a specific date
  Future<Set<String>> getCompletedExercisesForDate(String dateKey) async {
    final attempts = await _repo.fetchAttemptsForDate(dateKey);
    return attempts
        .where((a) => a.countsForDailyEffort)
        .map((a) => a.exerciseId)
        .toSet();
  }

  /// Get today's completed exercises (date-scoped: only sessions with countedForDailyEffort today)
  Future<Set<String>> getTodayCompletedExercises() async {
    final today = DailyCompletionUtils.getTodayDateKey();
    return getCompletedExercisesForDate(today);
  }

  /// Get completed sessions for the last N days (for daily plan anti-repetition / weekly balance).
  /// Returns one [CompletedSession] per attempt that has dateKey and categoryId.
  Future<List<CompletedSession>> getLast7DaysCompletedSessions() async {
    await ensureLoaded();
    final now = DateTime.now();
    final sessions = <CompletedSession>[];
    for (var i = 0; i < 7; i++) {
      final d = now.subtract(Duration(days: i));
      final dateKey = DailyCompletionUtils.generateDateKey(d);
      final attempts = await _repo.fetchAttemptsForDate(dateKey);
      for (final a in attempts) {
        if (a.categoryId.isNotEmpty) {
          sessions.add(CompletedSession(
            dateKey: dateKey,
            categoryId: a.categoryId,
            exerciseId: a.exerciseId,
          ));
        }
      }
    }
    return sessions;
  }
}
