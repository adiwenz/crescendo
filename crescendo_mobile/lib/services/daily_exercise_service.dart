import 'dart:math';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/daily_plan.dart';
import '../models/exercise.dart';
import '../models/vocal_exercise.dart';
import '../services/attempt_repository.dart';
import '../services/daily_plan_builder.dart';
import '../services/exercise_repository.dart';
import '../utils/daily_completion_utils.dart';

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

  final ExerciseRepository _exerciseRepo = ExerciseRepository();

  /// Debug mode: Offset days for testing (0 = today, 1 = tomorrow, -1 = yesterday)
  ///
  /// HOW TO USE:
  /// 1. Change this value (e.g., set to 1)
  /// 2. Hot restart the app (Cmd+Shift+F5 or click restart button)
  /// 3. The app will treat it as a new day and generate new exercises
  /// 4. Set back to 0 when done testing
  static int debugDayOffset = 1;

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

  /// Select daily exercises using Daily Plan: Warmup, Technique, Main Work, Finisher (one per role).
  Future<List<Exercise>> _selectDailyExercises() async {
    final today = _getTodayDateString();
    final adjustedDate = _getAdjustedDate();

    final history =
        await AttemptRepository.instance.getLast7DaysCompletedSessions();
    final plan = buildDailyPlan(
      date: adjustedDate,
      history: history,
      goal: null,
      fatigue: FatigueLevel.medium,
      pinnedWarmupCategoryId: null,
    );

    final allVocalExercises = _exerciseRepo.getExercises();
    final byCategory = <String, List<VocalExercise>>{};
    for (final ve in allVocalExercises) {
      byCategory.putIfAbsent(ve.categoryId, () => []).add(ve);
    }

    final seed = today.hashCode;
    final random = Random(seed);
    final selected = <Exercise>[];

    for (var i = 0; i < plan.slots.length && i < _numDailyExercises; i++) {
      final slot = plan.slots[i];
      final candidates = byCategory[slot.categoryId] ?? [];
      if (candidates.isEmpty) {
        if (kDebugMode) {
          debugPrint(
              '[DailyExerciseService] No exercises for category ${slot.categoryId}, slot ${slot.roleLabel}');
        }
        final fallback = allVocalExercises
            .where((e) => !selected.any((s) => s.id == e.id))
            .toList();
        if (fallback.isNotEmpty) {
          selected.add(_vocalExerciseToExercise(
              fallback[random.nextInt(fallback.length)]));
        }
        continue;
      }
      final picked = candidates[random.nextInt(candidates.length)];
      selected.add(_vocalExerciseToExercise(picked));
      if (kDebugMode) {
        debugPrint(
            '[DailyExerciseService] ${slot.roleLabel}: ${slot.categoryId} -> ${picked.name}');
      }
    }

    if (selected.length < _numDailyExercises) {
      final remaining = allVocalExercises
          .where((ve) => !selected.any((s) => s.id == ve.id))
          .map(_vocalExerciseToExercise)
          .toList();
      while (selected.length < _numDailyExercises && remaining.isNotEmpty) {
        selected.add(remaining.removeAt(random.nextInt(remaining.length)));
      }
    }

    if (kDebugMode) {
      debugPrint(
          '[DailyExerciseService] Plan: ${plan.slots.map((s) => '${s.roleLabel}:${s.categoryId}').join(', ')}');
      debugPrint(
          '[DailyExerciseService] Selected: ${selected.map((e) => e.title).join(', ')}');
    }

    return selected.take(_numDailyExercises).toList();
  }

  DateTime _getAdjustedDate() {
    final now = DateTime.now();
    return kDebugMode && debugDayOffset != 0
        ? now.add(Duration(days: debugDayOffset))
        : now;
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

  /// Get today's date as YYYY-MM-DD string (local timezone, same as daily checklist).
  /// In debug mode, can be offset using debugDayOffset.
  String _getTodayDateString() {
    final now = DateTime.now();
    final adjustedDate = kDebugMode && debugDayOffset != 0
        ? now.add(Duration(days: debugDayOffset))
        : now;
    final dateString = DailyCompletionUtils.generateDateKey(adjustedDate);
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
