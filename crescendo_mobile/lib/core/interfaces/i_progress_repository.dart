import 'dart:async';
import '../../models/exercise_attempt.dart';
import '../../models/exercise_score.dart';
import '../../models/exercise_take.dart';

abstract class IProgressRepository {
  Future<void> persistAttempt({
    required ExerciseAttempt attempt,
    int? level,
    int? score,
  });
  
  Future<List<ExerciseAttempt>> fetchAllAttempts();
  Future<List<ExerciseAttempt>> fetchAttemptSummaries();
  Future<ExerciseAttempt?> fetchAttempt(String id);
  Future<ExerciseTake?> fetchLastTake(String exerciseId);
  Future<List<ExerciseScore>> fetchScoreHistory(String exerciseId);
  Future<ExerciseScore?> fetchLastScore(String exerciseId);
  Future<int> countAttemptsForExercise(String exerciseId);
  Future<void> deleteAll();
}
