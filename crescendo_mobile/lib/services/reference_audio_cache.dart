import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/reference_note.dart';

/// Cache for pre-rendered reference audio to eliminate Start delay
/// 
/// Cache key is based on exercise parameters and note content.
/// Cache is in-memory only (files are temporary and cleaned up by OS).
class ReferenceAudioCache {
  static final ReferenceAudioCache instance = ReferenceAudioCache._();
  ReferenceAudioCache._();

  /// Cache entry: file path to rendered WAV
  final Map<String, String> _cache = {};

  /// Generate cache key from exercise parameters and notes
  String _generateKey({
    required String exerciseId,
    required String difficulty,
    required List<ReferenceNote> notes,
    required int sampleRate,
  }) {
    // Create a stable hash of the notes (startSec, endSec, midi)
    final noteData = notes.map((n) => {
      's': n.startSec,
      'e': n.endSec,
      'm': n.midi,
    }).toList();
    final noteJson = jsonEncode(noteData);
    final noteHash = sha256.convert(utf8.encode(noteJson)).toString().substring(0, 16);
    
    return '${exerciseId}_${difficulty}_${sampleRate}_$noteHash';
  }

  /// Get cached audio path, or null if not cached
  String? getCached({
    required String exerciseId,
    required String difficulty,
    required List<ReferenceNote> notes,
    required int sampleRate,
  }) {
    final key = _generateKey(
      exerciseId: exerciseId,
      difficulty: difficulty,
      notes: notes,
      sampleRate: sampleRate,
    );
    final path = _cache[key];
    
    // Verify file still exists
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) {
        return path;
      } else {
        // File was deleted, remove from cache
        _cache.remove(key);
      }
    }
    
    return null;
  }

  /// Store rendered audio path in cache
  void putCached({
    required String exerciseId,
    required String difficulty,
    required List<ReferenceNote> notes,
    required int sampleRate,
    required String audioPath,
  }) {
    final key = _generateKey(
      exerciseId: exerciseId,
      difficulty: difficulty,
      notes: notes,
      sampleRate: sampleRate,
    );
    _cache[key] = audioPath;
  }

  /// Clear all cached entries (useful for testing or memory management)
  void clear() {
    _cache.clear();
  }

  /// Get cache statistics (for debugging)
  int get size => _cache.length;
}
