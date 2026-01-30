import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_mobile/services/attempt_repository.dart';
import 'package:crescendo_mobile/services/progress_service.dart';
import 'package:crescendo_mobile/utils/daily_completion_utils.dart';
import '../test_bootstrap.dart';

void main() {
  setUpAll(() async {
    await bootstrapTests();
    DailyCompletionUtils.initialize();
  });

  setUp(() async {
    await resetTestDatabase();
  });

  group('Daily credit and today\'s completed exercises', () {
    test('getTodayCompletedExercises returns only exercises with daily credit for today', () async {
      final progressService = ProgressService();
      final today = DailyCompletionUtils.getTodayDateKey();
      final now = DateTime.now();

      // Persist an attempt that counts for daily effort today
      final attempt = progressService.buildAttempt(
        exerciseId: 'breath_1',
        categoryId: 'breath',
        startedAt: now.subtract(const Duration(minutes: 1)),
        completedAt: now,
        overallScore: 100,
        dateKey: today,
        countsForDailyEffort: true,
        completionPercent: 1.0,
      );
      await progressService.saveAttempt(attempt);

      await AttemptRepository.instance.ensureLoaded();
      final completed = await AttemptRepository.instance.getTodayCompletedExercises();

      expect(completed.contains('breath_1'), true);
    });

    test('getTodayCompletedExercises excludes attempts that do not count for daily effort', () async {
      final progressService = ProgressService();
      final today = DailyCompletionUtils.getTodayDateKey();
      final now = DateTime.now();

      // Persist attempt that does NOT count for daily effort (e.g. quit early)
      final attempt = progressService.buildAttempt(
        exerciseId: 'breath_2',
        categoryId: 'breath',
        startedAt: now.subtract(const Duration(minutes: 1)),
        completedAt: now,
        overallScore: 50,
        dateKey: today,
        countsForDailyEffort: false,
        completionPercent: 0.5,
      );
      await progressService.saveAttempt(attempt);

      await AttemptRepository.instance.ensureLoaded();
      final completed = await AttemptRepository.instance.getTodayCompletedExercises();

      expect(completed.contains('breath_2'), false);
    });

    test('getCompletedExercisesForDate returns only credited exercises for that date', () async {
      final progressService = ProgressService();
      final today = DailyCompletionUtils.getTodayDateKey();
      final now = DateTime.now();

      final credited = progressService.buildAttempt(
        exerciseId: 'ex_credited',
        categoryId: 'cat',
        startedAt: now,
        completedAt: now,
        overallScore: 95,
        dateKey: today,
        countsForDailyEffort: true,
        completionPercent: 1.0,
      );
      final notCredited = progressService.buildAttempt(
        exerciseId: 'ex_not_credited',
        categoryId: 'cat',
        startedAt: now,
        completedAt: now,
        overallScore: 60,
        dateKey: today,
        countsForDailyEffort: false,
        completionPercent: 0.6,
      );
      await progressService.saveAttempt(credited);
      await progressService.saveAttempt(notCredited);

      final completed = await AttemptRepository.instance.getCompletedExercisesForDate(today);

      expect(completed.contains('ex_credited'), true);
      expect(completed.contains('ex_not_credited'), false);
    });

    test('getCompletedExercisesForDate with different dateKey returns empty when no data', () async {
      final progressService = ProgressService();
      final today = DailyCompletionUtils.getTodayDateKey();
      final now = DateTime.now();

      final attempt = progressService.buildAttempt(
        exerciseId: 'ex_today',
        categoryId: 'cat',
        startedAt: now,
        completedAt: now,
        overallScore: 95,
        dateKey: today,
        countsForDailyEffort: true,
        completionPercent: 1.0,
      );
      await progressService.saveAttempt(attempt);

      // Query a different date (e.g. yesterday)
      final otherDate = '2020-01-01';
      final completed = await AttemptRepository.instance.getCompletedExercisesForDate(otherDate);

      expect(completed.contains('ex_today'), false);
      expect(completed.isEmpty, true);
    });
  });
}
