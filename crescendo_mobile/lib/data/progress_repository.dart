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

  /// Unified transactional save for an attempt.
  /// Handles file assets and all DB updates (history, last_take, progress).
  Future<void> persistAttempt({
    required ExerciseAttempt attempt,
    int? level,
    int? score,
  }) async {
    final start = DateTime.now();
    debugPrint('[AttemptPersistence] SAVE_START exerciseId=${attempt.exerciseId} score=${attempt.overallScore} level=$level pathType=${level != null ? "full" : "partial/exit"}');

    try {
      // 1. Prepare assets (File I/O outside transaction)
      ExerciseTake? lastTake;
      if (attempt.recordingPath != null || attempt.contourJson != null) {
        lastTake = await _manageAssetsAndCreateTake(attempt);
      }

      final db = overrideDb ?? await _db.database;
      
      await db.transaction((txn) async {
        // 2. Insert into take_scores (History)
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

        // 3. Upsert last_take
        if (lastTake != null) {
          final toWrite = lastTake.toMap();
          if (kDebugMode) {
            // await _logLastTakeSchema(txn); // Reduce noise
            debugPrint('[AttemptPersistence] LastTake columns=${toWrite.keys.toList()}');
          }
          await txn.insert('last_take', toWrite, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // 4. Update Level Progress (if applicable)
        if (level != null && score != null) {
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
            debugPrint('[AttemptPersistence] Level Up! New level: ${level + 1}');
          }
        }
      });
      
      debugPrint('[AttemptPersistence] SAVE_COMMIT_OK duration=${DateTime.now().difference(start).inMilliseconds}ms');
      
      // 5. Diagnostics (Post-commit)
      if (kDebugMode) {
        final count = await countAttemptsForExercise(attempt.exerciseId);
        debugPrint('[AttemptPersistence] Post-save count for ${attempt.exerciseId}: $count');
        final recent = await fetchLastScore(attempt.exerciseId);
        debugPrint('[AttemptPersistence] Verified read-back: id=${recent?.id} score=${recent?.score}');
      }

    } catch (e, st) {
      debugPrint('[AttemptPersistence] SAVE_ERROR: $e\n$st');
      rethrow; // Propagate to UI for snackbar/error handling
    }
  }

  // Deprecated methods kept for compatibility during refactor, but should redirect or warn
  Future<void> saveCompleteAttempt({
    required ExerciseAttempt attempt,
    required int level,
    required int score,
  }) async {
    debugPrint('[ProgressRepository] DEPRECATED: call persistAttempt instead');
    return persistAttempt(attempt: attempt, level: level, score: score);
  }

  Future<void> saveAttempt(ExerciseAttempt attempt) async {
     debugPrint('[ProgressRepository] DEPRECATED: call persistAttempt instead');
     return persistAttempt(attempt: attempt);
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
