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

import '../services/exercise_level_progress_repository.dart';
import '../models/exercise_level_progress.dart';

class ProgressRepository {
  final AppDatabase _db = AppDatabase();
  final Database? overrideDb;

  ProgressRepository({this.overrideDb});

  static bool _schemaLogged = false;

  Future<void> _logLastTakeSchema(DatabaseExecutor db) async {
    if (_schemaLogged || !kDebugMode) return;
    try {
      final info = await db.rawQuery('PRAGMA table_info(last_take)');
      for (final row in info) {
        debugPrint('[LastTakeSchema] name=${row['name']} type=${row['type']} notnull=${row['notnull']} pk=${row['pk']}');
      }
      _schemaLogged = true;
    } catch (e) {
      debugPrint('[LastTakeSchema] Error fetching schema: $e');
    }
  }

  /// Transactional save of attempt + level progress
  Future<void> saveCompleteAttempt({
    required ExerciseAttempt attempt,
    required int level,
    required int score,
  }) async {
    final db = overrideDb ?? await _db.database;
    
    await db.transaction((txn) async {
       // 1. Save Attempt (Scores + Assets)
       // We duplicate saveAttempt logic here to use 'txn'
       final scoreObj = ExerciseScore(
        id: attempt.id,
        exerciseId: attempt.exerciseId,
        categoryId: attempt.categoryId,
        createdAt: attempt.completedAt ?? DateTime.now(),
        score: attempt.overallScore,
        durationMs: (attempt.completedAt != null && attempt.startedAt != null)
            ? attempt.completedAt!.difference(attempt.startedAt!).inMilliseconds
            : 0,
      );
      await txn.insert('take_scores', scoreObj.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

      if (attempt.recordingPath != null || attempt.contourJson != null) {
        if (kDebugMode) {
          debugPrint('[AttemptSave] exerciseId=${attempt.exerciseId} pitchDifficulty=${attempt.pitchDifficulty}');
        }
        final lastTake = await _manageAssetsAndCreateTake(attempt);
        final toWrite = lastTake.toMap();
        if (kDebugMode) {
          await _logLastTakeSchema(txn);
          debugPrint('[LastTakeWrite] columns=${toWrite.keys.toList()}');
          debugPrint('[LastTakeWrite] values=${toWrite.values.toList()}');
        }
        await txn.insert('last_take', toWrite, conflictAlgorithm: ConflictAlgorithm.replace);
        
        if (kDebugMode) {
          final persisted = await txn.query('last_take', where: 'exerciseId = ?', whereArgs: [attempt.exerciseId]);
          if (persisted.isNotEmpty) {
            debugPrint('[LastTakeWrite] persistedRow=${persisted.first}');
          } else {
             debugPrint('[LastTakeWrite] persistedRow=NULL (Read failed after write)');
          }
        }
      }

      // 2. Update Level Progress
      final levelRepo = ExerciseLevelProgressRepository(overrideDb: txn);
      final updated = await levelRepo.saveAttempt(
        exerciseId: attempt.exerciseId,
        level: level,
        score: score,
      );
      
      if (score > 90 &&
          level == updated.highestUnlockedLevel &&
          level < ExerciseLevelProgress.maxLevel) {
        await levelRepo.updateUnlockedLevel(
          exerciseId: attempt.exerciseId,
          newLevel: level + 1,
        );
      }
    });
  }

  Future<void> saveAttempt(ExerciseAttempt attempt) async {
    final db = overrideDb ?? await _db.database;
    
    // Use transaction for atomicity and speed
    await db.transaction((txn) async {
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
      await txn.insert('take_scores', score.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

      // 2. Manage assets and update last_take (UPSERT)
      // Only last_take needs to track file paths.
      // We don't save heavy blobs to exercise_attempts anymore.
      if (attempt.recordingPath != null || attempt.contourJson != null) {
        if (kDebugMode) {
           debugPrint('[AttemptSave] exerciseId=${attempt.exerciseId} pitchDifficulty=${attempt.pitchDifficulty}');
        }
        final lastTake = await _manageAssetsAndCreateTake(attempt);
        // UPSERT: Insert or replace based on PRIMARY KEY (exerciseId)
        // Schema must utilize exerciseId as primary key for this to work as an upsert on that key
        final toWrite = lastTake.toMap();
        if (kDebugMode) {
          await _logLastTakeSchema(txn);
          debugPrint('[LastTakeWrite] columns=${toWrite.keys.toList()}');
          debugPrint('[LastTakeWrite] values=${toWrite.values.toList()}');
        }
        await txn.insert('last_take', toWrite, conflictAlgorithm: ConflictAlgorithm.replace);

        if (kDebugMode) {
          final persisted = await txn.query('last_take', where: 'exerciseId = ?', whereArgs: [attempt.exerciseId]);
          if (persisted.isNotEmpty) {
            debugPrint('[LastTakeWrite] persistedRow=${persisted.first}');
          } else {
             debugPrint('[LastTakeWrite] persistedRow=NULL (Read failed after write)');
          }
        }
      }
    });
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
      minMidi: attempt.minMidi,
      maxMidi: attempt.maxMidi,
      referenceWavPath: attempt.referenceWavPath,
      referenceSampleRate: attempt.referenceSampleRate,
      referenceWavSha1: attempt.referenceWavSha1,
      pitchDifficulty: attempt.pitchDifficulty,
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
    
    // Ensure last_take has exerciseId as PRIMARY KEY for upsert
    // Note: If table exists without PK, we might need to recreate. 
    // Ideally this was set in migrations, but for safety we check.
    // Since we can't easily alter PK in sqlite, we assume it's set correctly or we just rely on Replace.
    // 'CREATE TABLE IF NOT EXISTS last_take (exerciseId TEXT PRIMARY KEY, ...)' should be in db.dart
    // If not, we might rely on the fact that ConflictAlgorithm.replace works if unique constraint exists.
    // For now, we trust the DB creation script.
  }
}

/// Helper for isolate-based parsing
List<ExerciseAttempt> _parseAttemptsIsolate(List<Map<String, Object?>> rows) {
  return rows.map((row) => ExerciseAttempt.fromDbMap(row)).toList();
}
