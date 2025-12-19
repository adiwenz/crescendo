import '../data/progress_repository.dart';
import '../models/exercise_attempt.dart';

/// Thin wrapper over ProgressRepository to expose latest attempts.
class AttemptRepository {
  AttemptRepository._();
  static final AttemptRepository instance = AttemptRepository._();

  final ProgressRepository _repo = ProgressRepository();
  List<ExerciseAttempt> _cache = const [];
  bool _loaded = false;

  List<ExerciseAttempt> get cache => _cache;

  Future<List<ExerciseAttempt>> refresh() async {
    _cache = await _repo.fetchAllAttempts();
    _loaded = true;
    return _cache;
  }

  Future<void> save(ExerciseAttempt attempt) async {
    await _repo.saveAttempt(attempt);
    _cache = [attempt, ..._cache.where((a) => a.id != attempt.id)];
    _loaded = true;
  }

  ExerciseAttempt? latestFor(String exerciseId) {
    for (final a in _cache) {
      if (a.exerciseId == exerciseId) return a;
    }
    return null;
  }

  List<ExerciseAttempt> recent({int limit = 10}) {
    return _cache.take(limit).toList();
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await refresh();
  }
}
