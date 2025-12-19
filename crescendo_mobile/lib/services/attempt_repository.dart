import 'package:flutter/foundation.dart';

import '../data/progress_repository.dart';
import '../models/exercise_attempt.dart';

/// Thin wrapper over ProgressRepository to expose latest attempts.
class AttemptRepository extends ChangeNotifier {
  AttemptRepository._();
  static final AttemptRepository instance = AttemptRepository._();

  final ProgressRepository _repo = ProgressRepository();
  List<ExerciseAttempt> _cache = const [];
  bool _loaded = false;
  int _revision = 0;

  List<ExerciseAttempt> get cache => _cache;
  int get revision => _revision;

  Future<List<ExerciseAttempt>> refresh() async {
    try {
      final attempts = await _repo.fetchAllAttempts();
      _cache = attempts;
      debugPrint('[AttemptRepository] refreshed: ${_cache.length} attempts (instance=${identityHashCode(this)})');
    } catch (e, st) {
      debugPrint('[AttemptRepository] refresh failed: $e\n$st');
    }
    _loaded = true;
    _revision++;
    notifyListeners();
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
    await refresh();
  }
}
