import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'logging_database.dart';

class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    
    debugPrint('[DB_TRACE] AppDatabase opening...');
    final start = DateTime.now();
    
    final path = p.join(await getDatabasesPath(), 'crescendo.db');
    final realDb = await openDatabase(path, version: 11, onCreate: _onCreate, onUpgrade: _onUpgrade);
    
    debugPrint('[DB_TRACE] AppDatabase opened in ${DateTime.now().difference(start).inMilliseconds}ms');

    if (kDebugMode) {
       _db = LoggingDatabase(realDb);
    } else {
       _db = realDb;
    }
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE take_scores(
        id TEXT PRIMARY KEY,
        exerciseId TEXT,
        categoryId TEXT,
        createdAt INTEGER,
        score REAL,
        durationMs INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE last_take(
        exerciseId TEXT PRIMARY KEY,
        createdAt INTEGER,
        score REAL,
        audioPath TEXT,
        pitchPath TEXT,
        offsetMs REAL
      )
    ''');
    await db.execute('''
      CREATE TABLE takes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        createdAt TEXT,
        warmupId TEXT,
        warmupName TEXT,
        audioPath TEXT,
        framesJson TEXT,
        metricsJson TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE exercise_attempts(
        id TEXT PRIMARY KEY,
        exerciseId TEXT,
        categoryId TEXT,
        startedAt INTEGER,
        completedAt INTEGER,
        overallScore REAL,
        subScoresJson TEXT,
        notes TEXT,
        pitchDifficulty TEXT,
        recordingPath TEXT,
        contourJson TEXT,
        targetNotesJson TEXT,
        segmentsJson TEXT,
        recorderStartSec REAL,
        version INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE exercise_progress(
        exerciseId TEXT PRIMARY KEY,
        highestUnlockedLevel INTEGER,
        lastSelectedLevel INTEGER,
        bestScoresJson TEXT,
        lastScoresJson TEXT,
        attemptsJson TEXT,
        updatedAt INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE reference_audio_cache(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        exerciseId TEXT NOT NULL,
        rangeHash TEXT NOT NULL,
        variantKey TEXT NOT NULL,
        filePath TEXT NOT NULL,
        durationMs INTEGER NOT NULL,
        sampleRate INTEGER NOT NULL,
        codec TEXT NOT NULL,
        generatedAt INTEGER NOT NULL,
        version INTEGER NOT NULL,
        UNIQUE(exerciseId, rangeHash, variantKey)
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_reference_audio_cache_lookup 
      ON reference_audio_cache(exerciseId, rangeHash, variantKey)
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE exercise_attempts(
          id TEXT PRIMARY KEY,
          exerciseId TEXT,
          categoryId TEXT,
          startedAt INTEGER,
          completedAt INTEGER,
          overallScore REAL,
          subScoresJson TEXT,
          notes TEXT,
          pitchDifficulty TEXT,
          recordingPath TEXT,
          contourJson TEXT,
          version INTEGER
        )
      ''');
    }
    if (oldVersion >= 2 && oldVersion < 3) {
      await _addColumnIfMissing(db, 'exercise_attempts', 'pitchDifficulty', 'TEXT');
    }
    if (oldVersion < 4) {
      await _addColumnIfMissing(db, 'exercise_attempts', 'recordingPath', 'TEXT');
      await _addColumnIfMissing(db, 'exercise_attempts', 'contourJson', 'TEXT');
      await _addColumnIfMissing(db, 'exercise_attempts', 'startedAt', 'INTEGER');
      await _addColumnIfMissing(db, 'exercise_attempts', 'completedAt', 'INTEGER');
    }
    if (oldVersion < 8) {
      await _addColumnIfMissing(db, 'exercise_attempts', 'targetNotesJson', 'TEXT');
      await _addColumnIfMissing(db, 'exercise_attempts', 'segmentsJson', 'TEXT');
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS exercise_progress(
          exerciseId TEXT PRIMARY KEY,
          highestUnlockedLevel INTEGER,
          lastSelectedLevel INTEGER,
          bestScoresJson TEXT,
          lastScoresJson TEXT,
          attemptsJson TEXT,
          updatedAt INTEGER
        )
      ''');
    }
    if (oldVersion < 7) {
      await _addColumnIfMissing(db, 'exercise_progress', 'lastSelectedLevel', 'INTEGER');
    }
    if (oldVersion < 9) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS reference_audio_cache(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          exerciseId TEXT NOT NULL,
          rangeHash TEXT NOT NULL,
          variantKey TEXT NOT NULL,
          filePath TEXT NOT NULL,
          durationMs INTEGER NOT NULL,
          sampleRate INTEGER NOT NULL,
          codec TEXT NOT NULL,
          generatedAt INTEGER NOT NULL,
          version INTEGER NOT NULL,
          UNIQUE(exerciseId, rangeHash, variantKey)
        )
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_reference_audio_cache_lookup 
        ON reference_audio_cache(exerciseId, rangeHash, variantKey)
      ''');
    }
    if (oldVersion < 10) {
      await _addColumnIfMissing(db, 'exercise_attempts', 'recorderStartSec', 'REAL');
    }
    if (oldVersion < 11) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS take_scores(
          id TEXT PRIMARY KEY,
          exerciseId TEXT,
          categoryId TEXT,
          createdAt INTEGER,
          score REAL,
          durationMs INTEGER
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS last_take(
          exerciseId TEXT PRIMARY KEY,
          createdAt INTEGER,
          score REAL,
          audioPath TEXT,
          pitchPath TEXT,
          offsetMs REAL
        )
      ''');

      // Migrate scores
      await db.execute('''
        INSERT INTO take_scores (id, exerciseId, categoryId, createdAt, score, durationMs)
        SELECT id, exerciseId, categoryId, completedAt, overallScore, (completedAt - startedAt)
        FROM exercise_attempts
        WHERE completedAt IS NOT NULL AND startedAt IS NOT NULL
      ''');

      // Migrate last takes
      // We'll pick the latest completion for each exercise
      await db.execute('''
        INSERT OR REPLACE INTO last_take (exerciseId, createdAt, score, audioPath, pitchPath, offsetMs)
        SELECT ea.exerciseId, ea.completedAt, ea.overallScore, ea.recordingPath, '', ea.recorderStartSec
        FROM exercise_attempts ea
        INNER JOIN (
          SELECT exerciseId, MAX(completedAt) as lastComp
          FROM exercise_attempts
          GROUP BY exerciseId
        ) latest ON ea.exerciseId = latest.exerciseId AND ea.completedAt = latest.lastComp
      ''');
    }
  }

  Future<bool> _hasColumn(Database db, String table, String column) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    for (final row in info) {
      if (row['name'] == column) return true;
    }
    return false;
  }

  Future<void> _addColumnIfMissing(Database db, String table, String column, String type) async {
    final exists = await _hasColumn(db, table, column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }
}
