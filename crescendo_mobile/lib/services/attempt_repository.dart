import '../data/progress_repository.dart';
import '../models/exercise_attempt.dart';

/// Thin wrapper over ProgressRepository to expose latest attempts.
class AttemptRepository {
  AttemptRepository._();
  static final AttemptRepository instance = AttemptRepository._();

  final ProgressRepository _repo = ProgressRepository();
  List<ExerciseAttempt> _cache = const [];

  Future<List<ExerciseAttempt>> refresh() async {
    _cache = await _repo.fetchAllAttempts();
    return _cache;
  }

  Future<void> save(ExerciseAttempt attempt) async {
    await _repo.saveAttempt(attempt);
    _cache = [attempt, ..._cache.where((a) => a.id != attempt.id)];
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
}
