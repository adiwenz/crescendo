import 'package:sqflite/sqflite.dart';

import '../models/exercise_attempt.dart';
import '../services/storage/db.dart';

class ProgressRepository {
  final AppDatabase _db = AppDatabase();
  final Database? overrideDb;

  ProgressRepository({this.overrideDb});

  Future<void> saveAttempt(ExerciseAttempt attempt) async {
    final db = overrideDb ?? await _db.database;
    await db.insert(
      'exercise_attempts',
      attempt.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ExerciseAttempt>> fetchAllAttempts() async {
    final db = overrideDb ?? await _db.database;
    final rows = await db.query('exercise_attempts', orderBy: 'completedAt DESC');
    return rows.map((row) => ExerciseAttempt.fromMap(row)).toList();
  }

  Future<List<ExerciseAttempt>> fetchAttemptsForExercise(String exerciseId) async {
    final db = overrideDb ?? await _db.database;
    final rows = await db.query(
      'exercise_attempts',
      where: 'exerciseId = ?',
      whereArgs: [exerciseId],
      orderBy: 'completedAt DESC',
    );
    return rows.map((row) => ExerciseAttempt.fromMap(row)).toList();
  }

  Future<void> deleteAll() async {
    final db = overrideDb ?? await _db.database;
    await db.delete('exercise_attempts');
  }
}
