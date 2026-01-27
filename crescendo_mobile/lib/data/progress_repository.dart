import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:async';

import '../models/exercise_attempt.dart';
import '../services/storage/db.dart';

class ProgressRepository {
  final AppDatabase _db = AppDatabase();
  final Database? overrideDb;

  ProgressRepository({this.overrideDb});

  Future<void> saveAttempt(ExerciseAttempt attempt) async {
    final db = overrideDb ?? await _db.database;
    await _ensureMigrated(db);
    await db.insert(
      'exercise_attempts',
      attempt.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ExerciseAttempt>> fetchAllAttempts() async {
    final db = overrideDb ?? await _db.database;
    await _ensureMigrated(db);
    final rows = await db.query('exercise_attempts', orderBy: 'completedAt DESC');
    return compute(_parseAttemptsIsolate, rows);
  }

  Future<List<ExerciseAttempt>> fetchAttemptSummaries() async {
    final db = overrideDb ?? await _db.database;
    await _ensureMigrated(db);
    // Exclude heavy JSON columns: contourJson, targetNotesJson, segmentsJson
    final rows = await db.query(
      'exercise_attempts',
      columns: [
        'id', 'exerciseId', 'categoryId', 'startedAt', 'completedAt',
        'overallScore', 'subScoresJson', 'notes', 'pitchDifficulty',
        'recordingPath', 'version'
      ],
      orderBy: 'completedAt DESC'
    );
    return compute(_parseAttemptsIsolate, rows);
  }

  Future<ExerciseAttempt?> fetchAttempt(String id) async {
    final db = overrideDb ?? await _db.database;
    await _ensureMigrated(db);
    final rows = await db.query(
      'exercise_attempts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1
    );
    if (rows.isEmpty) return null;
    return ExerciseAttempt.fromDbMap(rows.first, onWarning: _logWarn);
  }

  Future<List<ExerciseAttempt>> fetchAttemptsForExercise(String exerciseId) async {
    final db = overrideDb ?? await _db.database;
    await _ensureMigrated(db);
    final rows = await db.query(
      'exercise_attempts',
      where: 'exerciseId = ?',
      whereArgs: [exerciseId],
      orderBy: 'completedAt DESC',
    );
    return compute(_parseAttemptsIsolate, rows);
  }

  Future<int> countAttemptsForExercise(String exerciseId) async {
    final db = overrideDb ?? await _db.database;
    await _ensureMigrated(db);
    final res = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM exercise_attempts WHERE exerciseId = ?',
      [exerciseId],
    );
    final count = Sqflite.firstIntValue(res) ?? 0;
    return count;
  }

  Future<void> deleteAll() async {
    final db = overrideDb ?? await _db.database;
    await _ensureMigrated(db);
    await db.delete('exercise_attempts');
  }

  Future<void> validateAttempts() async {
    final db = overrideDb ?? await _db.database;
    await _ensureMigrated(db);
    final rows = await db.query('exercise_attempts');
    for (final row in rows) {
      try {
        ExerciseAttempt.fromDbMap(row, onWarning: _logWarn);
      } catch (e, st) {
        debugPrint('validateAttempts parse error for id=${row['id']}: $e\n$st');
      }
    }
  }

  void _logWarn(String msg) {
    debugPrint('ExerciseAttempt parse warning: $msg');
  }

  Future<void> _ensureMigrated(Database db) async {
    const required = {
      'id': 'TEXT',
      'exerciseId': 'TEXT',
      'categoryId': 'TEXT',
      'startedAt': 'INTEGER',
      'completedAt': 'INTEGER',
      'overallScore': 'REAL',
      'subScoresJson': 'TEXT',
      'notes': 'TEXT',
      'pitchDifficulty': 'TEXT',
      'recordingPath': 'TEXT',
      'contourJson': 'TEXT',
      'targetNotesJson': 'TEXT',
      'segmentsJson': 'TEXT',
      'version': 'INTEGER',
    };
    final info = await db.rawQuery('PRAGMA table_info(exercise_attempts)');
    final existing = {for (final row in info) row['name'] as String: row['type'] as String?};
    if (existing.isEmpty) {
      // Table missing: create fresh with id primary key
      await db.execute('''
        CREATE TABLE IF NOT EXISTS exercise_attempts(
          id TEXT PRIMARY KEY,
          exerciseId TEXT,
          categoryId TEXT,
          startedAt INTEGER,
          completedAt INTEGER,
          overallScore REAL,
          subScoresJson TEXT,
          notes TEXT,
          pitchDifficulty TEXT,
          version INTEGER
        )
      ''');
      return;
    }
    for (final entry in required.entries) {
      if (!existing.keys.contains(entry.key)) {
        await db.execute('ALTER TABLE exercise_attempts ADD COLUMN ${entry.key} ${entry.value}');
      }
    }
  }
}

/// Helper for isolate-based parsing
List<ExerciseAttempt> _parseAttemptsIsolate(List<Map<String, Object?>> rows) {
  return rows.map((row) => ExerciseAttempt.fromDbMap(row)).toList();
}
