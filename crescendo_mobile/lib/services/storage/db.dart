import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'crescendo.db');
    _db = await openDatabase(path, version: 3, onCreate: _onCreate, onUpgrade: _onUpgrade);
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
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
        startedAt TEXT,
        completedAt TEXT,
        overallScore REAL,
        subScoresJson TEXT,
        notes TEXT,
        pitchDifficulty TEXT,
        version INTEGER
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE exercise_attempts(
          id TEXT PRIMARY KEY,
          exerciseId TEXT,
          categoryId TEXT,
          startedAt TEXT,
          completedAt TEXT,
          overallScore REAL,
          subScoresJson TEXT,
          notes TEXT,
          pitchDifficulty TEXT,
          version INTEGER
        )
      ''');
    }
    if (oldVersion >= 2 && oldVersion < 3) {
      await db.execute('ALTER TABLE exercise_attempts ADD COLUMN pitchDifficulty TEXT');
    }
  }
}
