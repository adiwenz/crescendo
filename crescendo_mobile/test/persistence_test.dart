import 'package:crescendo_mobile/models/metrics.dart';
import 'package:crescendo_mobile/models/pitch_frame.dart';
import 'package:crescendo_mobile/models/take.dart';
import 'package:crescendo_mobile/services/storage/take_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('persistence roundtrip', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, v) async {
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
      },
    ));

    final repo = TakeRepository(overrideDb: db);
    final take = Take(
      name: 'test',
      createdAt: DateTime.parse('2024-01-01T00:00:00Z'),
      warmupId: 'w',
      warmupName: 'Warmup',
      audioPath: '/tmp/a.wav',
      frames: [PitchFrame(time: 0, hz: 440, midi: 69, centsError: 0)],
      metrics: Metrics(score: 95, meanAbsCents: 12, pctWithin20: 80, pctWithin50: 95, validFrames: 1),
    );
    final id = await repo.insert(take);
    final fetched = await repo.fetchById(id);
    expect(fetched, isNotNull);
    expect(fetched!.name, 'test');
    expect(fetched.metrics.score, 95);
  });
}
