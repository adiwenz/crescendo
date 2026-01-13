import 'dart:math';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/exercise.dart';
import '../services/exercise_repository.dart';

/// Service for selecting daily exercises deterministically based on the current date.
///
/// Features:
/// - Always includes a Warmup exercise as the first item
/// - Rotates through warmup exercises daily
/// - Selects remaining exercises randomly with category diversity
/// - Persists selections per day (YYYY-MM-DD)
/// - Supports debug mode for testing daily rotation
///
/// ============================================================================
/// DEBUGGING INSTRUCTIONS:
/// ============================================================================
///
/// Method 1: Change debugDayOffset in code (then hot restart)
/// -----------------------------------------------------------
/// In daily_exercise_service.dart, change this line:
///   static int debugDayOffset = 0;  // Change to 1 for tomorrow, -1 for yesterday
/// Then hot restart the app (not just hot reload).
///
/// Method 2: Call clearDailyExercises() from code (then hot restart)
/// ------------------------------------------------------------------
/// Add this to your Home screen initState or a debug button:
///   await dailyExerciseService.clearDailyExercises();
/// Then hot restart the app.
///
/// Method 3: Use Flutter DevTools or terminal
/// -------------------------------------------
/// In terminal, run:
///   flutter run --dart-define=FORCE_NEW_DAY=true
/// Or use Flutter DevTools to inspect SharedPreferences and manually clear:
///   Keys to clear: 'daily_exercises' and 'daily_exercises_date'
///
/// Method 4: Add a debug button (temporary)
/// -----------------------------------------
/// Add this widget temporarily to your Home screen for testing:
///   ElevatedButton(
///     onPressed: () async {
///       await dailyExerciseService.clearDailyExercises();
///       setState(() {}); // Refresh the screen
///     },
///     child: Text('Force New Day (Debug)'),
///   )
///
/// ============================================================================
class DailyExerciseService {
  static const String _dailyExercisesKey = 'daily_exercises';
  static const String _dailyExercisesDateKey = 'daily_exercises_date';
  static const int _numDailyExercises = 4;

  // Warmup category mapping: 'warmup' category maps to 'recovery_therapy' in VocalExercise
  static const String _warmupCategoryId = 'recovery_therapy';

  final ExerciseRepository _exerciseRepo = ExerciseRepository();

  /// Debug mode: Offset days for testing (0 = today, 1 = tomorrow, -1 = yesterday)
  ///
  /// HOW TO USE:
  /// 1. Change this value (e.g., set to 1)
  /// 2. Hot restart the app (Cmd+Shift+F5 or click restart button)
  /// 3. The app will treat it as a new day and generate new exercises
  /// 4. Set back to 0 when done testing
  static int debugDayOffset = 0;

  /// Get today's selected exercises. Returns the same exercises for the entire day.
  ///
  /// The first exercise is always a Warmup, followed by N-1 randomly selected exercises.
  Future<List<Exercise>> getTodaysExercises() async {
    final today = _getTodayDateString();
    final prefs = await SharedPreferences.getInstance();

    // Check if we have exercises for today
    final savedDate = prefs.getString(_dailyExercisesDateKey);
    if (savedDate == today) {
      final savedIds = prefs.getStringList(_dailyExercisesKey);
      if (savedIds != null && savedIds.length == _numDailyExercises) {
        // Return saved exercises for today
        final exercises = _getExercisesByIds(savedIds);
        if (kDebugMode) {
          debugPrint(
              '[DailyExerciseService] Using cached exercises for $today');
          debugPrint(
              '[DailyExerciseService] Exercises: ${exercises.map((e) => e.title).join(", ")}');
        }
        return exercises;
      }
    }

    // Generate new exercises for today
    if (kDebugMode) {
      debugPrint('[DailyExerciseService] Generating new exercises for $today');
    }
    final selected = await _selectDailyExercises();
    await _saveTodaysExercises(prefs, today, selected);
    return selected;
  }

  /// Select daily exercises: Warmup first, then N-1 random exercises.
  Future<List<Exercise>> _selectDailyExercises() async {
    // Get all exercises from the library
    final allVocalExercises = _exerciseRepo.getExercises();
    final allExercises =
        allVocalExercises.map((ve) => _vocalExerciseToExercise(ve)).toList();

    if (allExercises.length < _numDailyExercises) {
      return allExercises;
    }

    // Seed random with today's date for deterministic selection
    final today = _getTodayDateString();
    final seed = today.hashCode;
    final random = Random(seed);

    final selected = <Exercise>[];

    // STEP 1: Always select a Warmup exercise first
    // Warmup exercises are from 'recovery_therapy' category
    final warmupExercises =
        allExercises.where((e) => e.categoryId == _warmupCategoryId).toList();

    if (warmupExercises.isEmpty) {
      // Debug: Log if no warmup exercises found
      debugPrint(
          '[DailyExerciseService] ERROR: No warmup exercises found with categoryId: $_warmupCategoryId');
      debugPrint(
          '[DailyExerciseService] Available categories: ${allExercises.map((e) => e.categoryId).toSet().join(", ")}');
      // Don't add a non-warmup exercise - this is an error condition
      // Instead, try to find any exercise with 'warmup' in name or tags
      final fallbackWarmup = allExercises.firstWhere(
        (e) =>
            e.title.toLowerCase().contains('warmup') ||
            e.title.toLowerCase().contains('recovery'),
        orElse: () => allExercises.first,
      );
      selected.add(fallbackWarmup);
      debugPrint(
          '[DailyExerciseService] Using fallback warmup: ${fallbackWarmup.title}');
    } else {
      // Rotate through warmup exercises based on day
      // This ensures variety while staying deterministic
      final warmupIndex = (seed.abs()) % warmupExercises.length;
      final selectedWarmup = warmupExercises[warmupIndex];
      selected.add(selectedWarmup);
      if (kDebugMode) {
        debugPrint(
            '[DailyExerciseService] Selected warmup: ${selectedWarmup.title} (index: $warmupIndex of ${warmupExercises.length})');
        debugPrint(
            '[DailyExerciseService] Available warmups: ${warmupExercises.map((e) => e.title).join(", ")}');
      }
    }

    // STEP 2: Select remaining N-1 exercises randomly with category diversity
    final selectedIds = selected.map((e) => e.id).toSet();
    final remainingExercises =
        allExercises.where((e) => !selectedIds.contains(e.id)).toList();

    if (remainingExercises.length < _numDailyExercises - 1) {
      // Not enough exercises, just add what we have
      selected.addAll(remainingExercises);
      return selected;
    }

    // Group remaining exercises by category for diversity
    final byCategory = <String, List<Exercise>>{};
    for (final ex in remainingExercises) {
      byCategory.putIfAbsent(ex.categoryId, () => []).add(ex);
    }

    final usedCategories = <String>{};
    final shuffledCategories = List<String>.from(byCategory.keys)
      ..shuffle(random);

    // Try to pick one from each category first for variety
    for (final categoryId in shuffledCategories) {
      if (selected.length >= _numDailyExercises) break;

      final categoryExercises = byCategory[categoryId]!;
      if (categoryExercises.isNotEmpty) {
        final picked =
            categoryExercises[random.nextInt(categoryExercises.length)];
        selected.add(picked);
        selectedIds.add(picked.id);
        usedCategories.add(categoryId);
      }
    }

    // Fill remaining slots with any exercises
    final stillRemaining =
        remainingExercises.where((e) => !selectedIds.contains(e.id)).toList();
    stillRemaining.shuffle(random);

    while (selected.length < _numDailyExercises && stillRemaining.isNotEmpty) {
      selected.add(stillRemaining.removeAt(0));
    }

    if (kDebugMode) {
      debugPrint(
          '[DailyExerciseService] Selected exercises: ${selected.map((e) => e.title).join(", ")}');
    }

    return selected.take(_numDailyExercises).toList();
  }

  /// Convert VocalExercise to Exercise model for Home screen display.
  /// Maps exercise category to the corresponding Category bannerStyleId for consistent colors.
  Exercise _vocalExerciseToExercise(dynamic vocalEx) {
    return Exercise(
      id: vocalEx.id,
      categoryId: vocalEx.categoryId,
      title: vocalEx.name,
      subtitle: vocalEx.description,
      bannerStyleId: _getBannerStyleIdForCategory(vocalEx.categoryId),
    );
  }

  /// Map VocalExercise categoryId to Category bannerStyleId for consistent colors.
  /// This ensures exercises from the same category have the same color as their category tile.
  ///
  /// Uses the category's sortOrder to determine bannerStyleId, matching the color used
  /// in category tiles on the Explore screen.
  int _getBannerStyleIdForCategory(String vocalExerciseCategoryId) {
    try {
      final category = _exerciseRepo.getCategory(vocalExerciseCategoryId);
      return category.sortOrder % 8;
    } catch (e) {
      // Fallback to hash if category not found
      return vocalExerciseCategoryId.hashCode.abs() % 8;
    }
  }

  /// Get exercises by their IDs.
  List<Exercise> _getExercisesByIds(List<String> ids) {
    final allVocalExercises = _exerciseRepo.getExercises();
    final allExercises =
        allVocalExercises.map((ve) => _vocalExerciseToExercise(ve)).toList();
    final exerciseMap = {for (var ex in allExercises) ex.id: ex};
    return ids.map((id) => exerciseMap[id]!).whereType<Exercise>().toList();
  }

  /// Save today's exercises to SharedPreferences.
  Future<void> _saveTodaysExercises(
    SharedPreferences prefs,
    String date,
    List<Exercise> exercises,
  ) async {
    await prefs.setString(_dailyExercisesDateKey, date);
    await prefs.setStringList(
        _dailyExercisesKey, exercises.map((e) => e.id).toList());
    if (kDebugMode) {
      debugPrint(
          '[DailyExerciseService] Saved exercises for $date: ${exercises.map((e) => e.title).join(", ")}');
    }
  }

  /// Get today's date as YYYY-MM-DD string.
  /// In debug mode, can be offset using debugDayOffset.
  String _getTodayDateString() {
    final now = DateTime.now();
    final adjustedDate = kDebugMode && debugDayOffset != 0
        ? now.add(Duration(days: debugDayOffset))
        : now;
    final dateString =
        '${adjustedDate.year}-${adjustedDate.month.toString().padLeft(2, '0')}-${adjustedDate.day.toString().padLeft(2, '0')}';
    if (kDebugMode && debugDayOffset != 0) {
      debugPrint(
          '[DailyExerciseService] Using debug date offset: $debugDayOffset days (date: $dateString)');
    }
    return dateString;
  }

  /// Clear stored daily exercises (useful for testing).
  /// This will force regeneration on next call to getTodaysExercises().
  ///
  /// Usage: Call this method, then hot restart the app to see new exercises.
  /// You can add this to a debug button or call it from initState temporarily.
  Future<void> clearDailyExercises() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dailyExercisesKey);
    await prefs.remove(_dailyExercisesDateKey);
    debugPrint('[DailyExerciseService] Cleared stored daily exercises');
  }

  /// Force regenerate exercises for testing (clears storage and returns new exercises).
  /// This is a convenience method that combines clearDailyExercises() and getTodaysExercises().
  ///
  /// Usage: Call this method, then hot restart the app to see new exercises.
  Future<List<Exercise>> forceRegenerateExercises() async {
    await clearDailyExercises();
    return await getTodaysExercises();
  }

  /// Calculate remaining time in minutes for today's exercises.
  ///
  /// Returns the sum of estimated minutes for exercises that are not completed.
  /// Completed exercises contribute 0 minutes.
  ///
  /// [completedExerciseIds] - Set of exercise IDs that have been completed.
  /// Returns the total remaining minutes, or 0 if all exercises are completed.
  int calculateRemainingMinutes(
      List<Exercise> exercises, Set<String> completedExerciseIds) {
    if (exercises.isEmpty) return 0;

    int totalMinutes = 0;
    for (final exercise in exercises) {
      // Skip completed exercises
      if (completedExerciseIds.contains(exercise.id)) {
        continue;
      }

      // Get the VocalExercise to access estimatedMinutes
      try {
        final vocalExercise = _exerciseRepo.getExercise(exercise.id);
        totalMinutes += vocalExercise.estimatedMinutes;
      } catch (e) {
        // If exercise not found, skip it (don't crash)
        if (kDebugMode) {
          debugPrint(
              '[DailyExerciseService] Exercise ${exercise.id} not found, skipping from time calculation');
        }
      }
    }

    return totalMinutes;
  }
}

/// Global instance for easy access.
final dailyExerciseService = DailyExerciseService();
