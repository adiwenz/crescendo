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
    _db = await openDatabase(path, version: 1, onCreate: _onCreate);
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
  }
}
