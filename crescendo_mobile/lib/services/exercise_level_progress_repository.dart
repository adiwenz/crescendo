import 'package:sqflite/sqflite.dart';

import '../models/exercise_level_progress.dart';
import '../services/storage/db.dart';

class ExerciseLevelProgressRepository {
  final AppDatabase _db = AppDatabase();
  final Database? overrideDb;

  ExerciseLevelProgressRepository({this.overrideDb});

  Future<ExerciseLevelProgress> getExerciseProgress(String exerciseId) async {
    final db = overrideDb ?? await _db.database;
    final rows = await db.query(
      'exercise_progress',
      where: 'exerciseId = ?',
      whereArgs: [exerciseId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return ExerciseLevelProgress.empty(exerciseId);
    }
    return ExerciseLevelProgress.fromDbMap(rows.first);
  }

  Future<ExerciseLevelProgress> saveAttempt({
    required String exerciseId,
    required int level,
    required int score,
  }) async {
    final db = overrideDb ?? await _db.database;
    final current = await getExerciseProgress(exerciseId);
    final clampedLevel = level.clamp(
      ExerciseLevelProgress.minLevel,
      ExerciseLevelProgress.maxLevel,
    );
    final clampedScore = score.clamp(0, 100);
    final nextBest = Map<int, int>.from(current.bestScoreByLevel);
    final nextLast = Map<int, int>.from(current.lastScoreByLevel);
    final nextAttempts = Map<int, int>.from(current.attemptsByLevel);
    final previousBest = nextBest[clampedLevel] ?? 0;
    if (clampedScore > previousBest) {
      nextBest[clampedLevel] = clampedScore;
    }
    nextLast[clampedLevel] = clampedScore;
    nextAttempts[clampedLevel] = (nextAttempts[clampedLevel] ?? 0) + 1;
    final updated = current.copyWith(
      bestScoreByLevel: nextBest,
      lastScoreByLevel: nextLast,
      attemptsByLevel: nextAttempts,
      updatedAt: DateTime.now(),
    );
    await db.insert(
      'exercise_progress',
      updated.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return updated;
  }

  Future<ExerciseLevelProgress> updateUnlockedLevel({
    required String exerciseId,
    required int newLevel,
  }) async {
    final db = overrideDb ?? await _db.database;
    final current = await getExerciseProgress(exerciseId);
    final clamped = newLevel.clamp(
      ExerciseLevelProgress.minLevel,
      ExerciseLevelProgress.maxLevel,
    );
    if (clamped <= current.highestUnlockedLevel) {
      return current;
    }
    final updated = current.copyWith(
      highestUnlockedLevel: clamped,
      updatedAt: DateTime.now(),
    );
    await db.insert(
      'exercise_progress',
      updated.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return updated;
  }

  Future<ExerciseLevelProgress> setLastSelectedLevel({
    required String exerciseId,
    required int level,
  }) async {
    final db = overrideDb ?? await _db.database;
    final current = await getExerciseProgress(exerciseId);
    final clamped = level.clamp(
      ExerciseLevelProgress.minLevel,
      ExerciseLevelProgress.maxLevel,
    );
    final updated = current.copyWith(
      lastSelectedLevel: clamped,
      updatedAt: DateTime.now(),
    );
    await db.insert(
      'exercise_progress',
      updated.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return updated;
  }
}
