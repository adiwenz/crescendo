import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/pattern_spec.dart';

/// Service to load and cache pattern JSON specifications.
class PatternSpecLoader {
  static final PatternSpecLoader instance = PatternSpecLoader._();
  PatternSpecLoader._();

  final Map<String, PatternSpec> _cache = {};

  /// Load pattern spec for an exercise.
  /// Returns null if pattern file doesn't exist.
  Future<PatternSpec?> loadPattern(String exerciseId) async {
    // Check cache first
    if (_cache.containsKey(exerciseId)) {
      return _cache[exerciseId];
    }

    try {
      // Try multiple possible asset paths
      final possiblePaths = [
        'assets/generated/exercise_xmap/${exerciseId}_pattern.json',
        'assets/audio/patterns/${exerciseId}_pattern.json',
      ];

      String? jsonString;
      for (final path in possiblePaths) {
        try {
          jsonString = await rootBundle.loadString(path);
          break;
        } catch (e) {
          // Try next path
          continue;
        }
      }

      if (jsonString == null) {
        debugPrint('[PatternSpecLoader] Pattern file not found for $exerciseId');
        return null;
      }

      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final spec = PatternSpec.fromJson(json);

      // Cache it
      _cache[exerciseId] = spec;

      debugPrint('[PatternSpecLoader] Loaded pattern for $exerciseId: ${spec.noteCount} notes, duration=${spec.patternDurationSec.toStringAsFixed(2)}s, gap=${spec.gapBetweenPatterns.toStringAsFixed(2)}s');
      return spec;
    } catch (e, stackTrace) {
      debugPrint('[PatternSpecLoader] Error loading pattern for $exerciseId: $e');
      debugPrint('[PatternSpecLoader] Stack trace: $stackTrace');
      return null;
    }
  }

  /// Clear the cache (useful for testing or when patterns change)
  void clearCache() {
    _cache.clear();
  }

  /// Clear cache for a specific exercise
  void clearCacheFor(String exerciseId) {
    _cache.remove(exerciseId);
  }
}
