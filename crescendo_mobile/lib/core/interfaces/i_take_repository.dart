import 'dart:async';
import '../../models/take.dart';

/// Interface for take persistence operations.
/// Allows testing without real database.
abstract class ITakeRepository {
  /// Insert a new take into the database.
  /// Returns the ID of the inserted take.
  Future<int> insert(Take take);

  /// Fetch all takes, ordered by creation date (newest first).
  Future<List<Take>> fetchAll();

  /// Fetch a take by its ID.
  /// Returns null if not found.
  Future<Take?> fetchById(int id);
}
