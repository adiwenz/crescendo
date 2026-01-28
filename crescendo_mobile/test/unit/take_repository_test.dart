import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_mobile/test/fakes/fake_take_repository.dart';
import 'package:crescendo_mobile/models/take.dart';

void main() {
  group('TakeRepository', () {
    late FakeTakeRepository repository;

    setUp(() {
      repository = FakeTakeRepository();
    });

    test('saving a take writes expected fields', () async {
      final now = DateTime(2025, 1, 1, 12, 0, 0);
      final take = Take(
        id: null,
        exerciseId: 'test_exercise',
        wavPath: '/test/path.wav',
        score: 85,
        createdAt: now,
        offsetMs: 100,
        pitchFramesJson: '[{"midi": 60, "time": 0.0}]',
      );

      final id = await repository.insert(take);

      expect(id, greaterThan(0));

      final retrieved = await repository.fetchById(id);
      expect(retrieved, isNotNull);
      expect(retrieved!.exerciseId, 'test_exercise');
      expect(retrieved.wavPath, '/test/path.wav');
      expect(retrieved.score, 85);
      expect(retrieved.createdAt, now);
      expect(retrieved.offsetMs, 100);
      expect(retrieved.pitchFramesJson, '[{"midi": 60, "time": 0.0}]');
    });

    test('querying progress returns correct aggregation', () async {
      final now = DateTime(2025, 1, 1);

      // Insert multiple takes for same exercise
      await repository.insert(Take(
        id: null,
        exerciseId: 'ex1',
        wavPath: '/test/1.wav',
        score: 60,
        createdAt: now,
        offsetMs: 0,
        pitchFramesJson: '[]',
      ));

      await repository.insert(Take(
        id: null,
        exerciseId: 'ex1',
        wavPath: '/test/2.wav',
        score: 80,
        createdAt: now.add(const Duration(minutes: 1)),
        offsetMs: 0,
        pitchFramesJson: '[]',
      ));

      await repository.insert(Take(
        id: null,
        exerciseId: 'ex1',
        wavPath: '/test/3.wav',
        score: 100,
        createdAt: now.add(const Duration(minutes: 2)),
        offsetMs: 0,
        pitchFramesJson: '[]',
      ));

      final takes = await repository.fetchAll();

      // Should return all takes, newest first
      expect(takes.length, 3);
      expect(takes[0].score, 100); // Newest
      expect(takes[1].score, 80);
      expect(takes[2].score, 60); // Oldest

      // Calculate average score
      final avgScore = takes.map((t) => t.score).reduce((a, b) => a + b) / takes.length;
      expect(avgScore, closeTo(80.0, 0.1));
    });

    test('edge case: no takes returns empty series', () async {
      final takes = await repository.fetchAll();

      expect(takes, isEmpty);
      // Should not crash
    });

    test('fetchById returns null for non-existent ID', () async {
      final take = await repository.fetchById(999);

      expect(take, isNull);
    });

    test('multiple inserts increment IDs', () async {
      final id1 = await repository.insert(Take(
        id: null,
        exerciseId: 'ex1',
        wavPath: '/test/1.wav',
        score: 60,
        createdAt: DateTime.now(),
        offsetMs: 0,
        pitchFramesJson: '[]',
      ));

      final id2 = await repository.insert(Take(
        id: null,
        exerciseId: 'ex2',
        wavPath: '/test/2.wav',
        score: 70,
        createdAt: DateTime.now(),
        offsetMs: 0,
        pitchFramesJson: '[]',
      ));

      expect(id2, greaterThan(id1));
    });
  });
}
