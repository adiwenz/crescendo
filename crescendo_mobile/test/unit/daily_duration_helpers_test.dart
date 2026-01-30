import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_mobile/models/exercise.dart';
import 'package:crescendo_mobile/services/daily_exercise_service.dart';

void main() {
  late List<Exercise> exercisesWithDurations;

  setUp(() {
    exercisesWithDurations = [
      const Exercise(
        id: 'ex_120',
        categoryId: 'cat',
        title: 'A',
        subtitle: '',
        bannerStyleId: 0,
        estimatedDurationSec: 120,
      ),
      const Exercise(
        id: 'ex_30',
        categoryId: 'cat',
        title: 'B',
        subtitle: '',
        bannerStyleId: 0,
        estimatedDurationSec: 30,
      ),
      const Exercise(
        id: 'ex_90',
        categoryId: 'cat',
        title: 'C',
        subtitle: '',
        bannerStyleId: 0,
        estimatedDurationSec: 90,
      ),
    ];
  });

  group('totalPlannedDurationSec', () {
    test('durations [120, 30, 90] => total 240 sec => 4 min', () {
      final totalSec = dailyExerciseService.totalPlannedDurationSec(exercisesWithDurations);
      expect(totalSec, 240);
      expect((totalSec / 60).ceil(), 4);
    });

    test('empty list => 0', () {
      expect(dailyExerciseService.totalPlannedDurationSec([]), 0);
    });
  });

  group('completedDurationSec', () {
    test('complete only 30s item => completed 30 sec', () {
      final completed = dailyExerciseService.completedDurationSec(
        exercisesWithDurations,
        {'ex_30'},
      );
      expect(completed, 30);
    });

    test('complete 120s + 90s => completed 210 sec', () {
      final completed = dailyExerciseService.completedDurationSec(
        exercisesWithDurations,
        {'ex_120', 'ex_90'},
      );
      expect(completed, 210);
    });

    test('complete none => 0', () {
      final completed = dailyExerciseService.completedDurationSec(
        exercisesWithDurations,
        {},
      );
      expect(completed, 0);
    });

    test('complete all => 240 sec', () {
      final completed = dailyExerciseService.completedDurationSec(
        exercisesWithDurations,
        {'ex_120', 'ex_30', 'ex_90'},
      );
      expect(completed, 240);
    });
  });

  group('time-based progress', () {
    test('complete only 30s item => progress = 30/240 = 0.125', () {
      final totalSec = dailyExerciseService.totalPlannedDurationSec(exercisesWithDurations);
      final completedSec = dailyExerciseService.completedDurationSec(
        exercisesWithDurations,
        {'ex_30'},
      );
      final progress = totalSec > 0 ? (completedSec / totalSec).clamp(0.0, 1.0) : 0.0;
      expect(progress, 0.125);
    });

    test('complete 120s + 90s => progress = 210/240 = 0.875', () {
      final totalSec = dailyExerciseService.totalPlannedDurationSec(exercisesWithDurations);
      final completedSec = dailyExerciseService.completedDurationSec(
        exercisesWithDurations,
        {'ex_120', 'ex_90'},
      );
      final progress = totalSec > 0 ? (completedSec / totalSec).clamp(0.0, 1.0) : 0.0;
      expect(progress, 0.875);
    });
  });

  group('calculateRemainingMinutes', () {
    test('complete only 30s => remaining 210 sec => 4 min', () {
      final mins = dailyExerciseService.calculateRemainingMinutes(
        exercisesWithDurations,
        {'ex_30'},
      );
      expect(mins, 4);
    });

    test('complete all => 0 min left', () {
      final mins = dailyExerciseService.calculateRemainingMinutes(
        exercisesWithDurations,
        {'ex_120', 'ex_30', 'ex_90'},
      );
      expect(mins, 0);
    });

    test('complete 120s + 90s => remaining 30 sec => 1 min', () {
      final mins = dailyExerciseService.calculateRemainingMinutes(
        exercisesWithDurations,
        {'ex_120', 'ex_90'},
      );
      expect(mins, 1);
    });
  });
}
