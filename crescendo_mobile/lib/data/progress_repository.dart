import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:async';

import '../models/exercise_attempt.dart';
import '../models/exercise_score.dart';
import '../models/exercise_take.dart';
import '../services/storage/db.dart';

class ProgressRepository {
  final AppDatabase _db = AppDatabase();
  final Database? overrideDb;

  ProgressRepository({this.overrideDb});

  Future<void> saveAttempt(ExerciseAttempt attempt) async {
    final db = overrideDb ?? await _db.database;
    
    // 1. Save lightweight score history
    final score = ExerciseScore(
      id: attempt.id,
      exerciseId: attempt.exerciseId,
      categoryId: attempt.categoryId,
      createdAt: attempt.completedAt ?? DateTime.now(),
      score: attempt.overallScore,
      durationMs: (attempt.completedAt != null && attempt.startedAt != null)
          ? attempt.completedAt!.difference(attempt.startedAt!).inMilliseconds
          : 0,
    );
    await db.insert('take_scores', score.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

    // 2. Manage assets and update last_take
    if (attempt.recordingPath != null || attempt.contourJson != null) {
      final lastTake = await _manageAssetsAndCreateTake(attempt);
      await db.insert('last_take', lastTake.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // 3. Keep old table for safety for one version, but we should eventually stop writing to it
    await db.insert(
      'exercise_attempts',
      attempt.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ExerciseTake> _manageAssetsAndCreateTake(ExerciseAttempt attempt) async {
    final docs = await getApplicationDocumentsDirectory();
    final baseDir = Directory(p.join(docs.path, 'last_take', attempt.exerciseId));
    if (!await baseDir.exists()) await baseDir.create(recursive: true);

    // Deterministic paths
    final audioFile = File(p.join(baseDir.path, 'audio.wav'));
    final pitchFile = File(p.join(baseDir.path, 'pitch.json'));

    // Move audio
    if (attempt.recordingPath != null) {
      final src = File(attempt.recordingPath!);
      if (await src.exists()) {
        await src.copy(audioFile.path);
        // Delete original to save space
        await src.delete();
      }
    }

    // Write pitch
    if (attempt.contourJson != null) {
      await pitchFile.writeAsString(attempt.contourJson!);
    }

    return ExerciseTake(
      exerciseId: attempt.exerciseId,
      createdAt: attempt.completedAt ?? DateTime.now(),
      score: attempt.overallScore,
      audioPath: audioFile.path,
      pitchPath: pitchFile.path,
      offsetMs: attempt.recorderStartSec ?? 0.0,
    );
  }

  Future<List<ExerciseScore>> fetchScoreHistory(String exerciseId) async {
    final db = overrideDb ?? await _db.database;
    final rows = await db.query(
      'take_scores',
      where: 'exerciseId = ?',
      whereArgs: [exerciseId],
      orderBy: 'createdAt DESC',
    );
    return rows.map((r) => ExerciseScore.fromMap(r)).toList();
  }

  Future<ExerciseTake?> fetchLastTake(String exerciseId) async {
    final db = overrideDb ?? await _db.database;
    final rows = await db.query(
      'last_take',
      where: 'exerciseId = ?',
      whereArgs: [exerciseId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ExerciseTake.fromMap(rows.first);
  }

  Future<List<ExerciseAttempt>> fetchAllAttempts() async {
    return fetchAttemptSummaries();
  }

  Future<List<ExerciseAttempt>> fetchAttemptSummaries() async {
    final db = overrideDb ?? await _db.database;
    final rows = await db.query('take_scores', orderBy: 'createdAt DESC');
    return rows.map((r) {
      final score = ExerciseScore.fromMap(r);
      return ExerciseAttempt(
        id: score.id,
        exerciseId: score.exerciseId,
        categoryId: score.categoryId,
        startedAt: score.createdAt.subtract(Duration(milliseconds: score.durationMs)),
        completedAt: score.createdAt,
        overallScore: score.score,
        subScores: const {}, // Lightweight summary doesn't need these
        version: 1,
      );
    }).toList();
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
    final rows = await db.query(
      'take_scores',
      where: 'exerciseId = ?',
      whereArgs: [exerciseId],
      orderBy: 'createdAt DESC',
    );
    return rows.map((r) {
      final score = ExerciseScore.fromMap(r);
      return ExerciseAttempt(
        id: score.id,
        exerciseId: score.exerciseId,
        categoryId: score.categoryId,
        startedAt: score.createdAt.subtract(Duration(milliseconds: score.durationMs)),
        completedAt: score.createdAt,
        overallScore: score.score,
      );
    }).toList();
  }

  Future<int> countAttemptsForExercise(String exerciseId) async {
    final db = overrideDb ?? await _db.database;
    final res = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM take_scores WHERE exerciseId = ?',
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

  Future<ExerciseScore?> fetchLastScore(String exerciseId) async {
    final db = overrideDb ?? await _db.database;
    final rows = await db.query(
      'take_scores',
      columns: ['id', 'score', 'createdAt'], // Only fetch needed fields
      where: 'exerciseId = ?',
      whereArgs: [exerciseId],
      orderBy: 'createdAt DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    
    // Construct minimal object
    final row = rows.first;
    return ExerciseScore(
      id: row['id'] as String? ?? '', // Get ID from table
      exerciseId: exerciseId,
      categoryId: '', 
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['createdAt'] as int),
      score: row['score'] as double,
      durationMs: 0,
    );
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
    } else {
      for (final entry in required.entries) {
        if (!existing.keys.contains(entry.key)) {
          await db.execute('ALTER TABLE exercise_attempts ADD COLUMN ${entry.key} ${entry.value}');
        }
      }
    }
    
    // Add index for fast per-exercise lookup
    await db.execute('CREATE INDEX IF NOT EXISTS idx_take_scores_exercise_created ON take_scores(exerciseId, createdAt DESC)');
  }
}

/// Helper for isolate-based parsing
List<ExerciseAttempt> _parseAttemptsIsolate(List<Map<String, Object?>> rows) {
  return rows.map((row) => ExerciseAttempt.fromDbMap(row)).toList();
}
