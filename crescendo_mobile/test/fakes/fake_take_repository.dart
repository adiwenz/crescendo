import 'dart:async';
import '../interfaces/i_take_repository.dart';
import '../../models/take.dart';

/// Fake take repository for testing.
/// Stores takes in memory.
class FakeTakeRepository implements ITakeRepository {
  final Map<int, Take> _takes = {};
  int _nextId = 1;

  @override
  Future<int> insert(Take take) async {
    final id = _nextId++;
    final takeWithId = Take(
      id: id,
      exerciseId: take.exerciseId,
      wavPath: take.wavPath,
      score: take.score,
      createdAt: take.createdAt,
      offsetMs: take.offsetMs,
      pitchFramesJson: take.pitchFramesJson,
    );
    _takes[id] = takeWithId;
    return id;
  }

  @override
  Future<List<Take>> fetchAll() async {
    final takes = _takes.values.toList();
    takes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return takes;
  }

  @override
  Future<Take?> fetchById(int id) async {
    return _takes[id];
  }

  /// Clear all takes (for test cleanup).
  void clear() {
    _takes.clear();
    _nextId = 1;
  }

  /// Get count of stored takes.
  int get count => _takes.length;
}
