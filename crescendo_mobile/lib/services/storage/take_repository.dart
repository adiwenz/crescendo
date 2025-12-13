import 'package:sqflite/sqflite.dart';

import '../../models/take.dart';
import 'db.dart';

class TakeRepository {
  final AppDatabase _db = AppDatabase();
  final Database? overrideDb;

  TakeRepository({this.overrideDb});

  Future<int> insert(Take take) async {
    final db = overrideDb ?? await _db.database;
    return db.insert('takes', take.toMap());
  }

  Future<List<Take>> fetchAll() async {
    final db = overrideDb ?? await _db.database;
    final maps = await db.query('takes', orderBy: 'createdAt DESC');
    return maps.map((m) => Take.fromMap(m)).toList();
  }

  Future<Take?> fetchById(int id) async {
    final db = overrideDb ?? await _db.database;
    final maps = await db.query('takes', where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return Take.fromMap(maps.first);
  }
}
