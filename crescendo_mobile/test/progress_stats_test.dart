import 'package:flutter_test/flutter_test.dart';

import 'package:crescendo_mobile/models/exercise_attempt.dart';
import 'package:crescendo_mobile/models/vocal_exercise.dart';
import 'package:crescendo_mobile/services/progress_stats.dart';

void main() {
  test('computeCategoryStats averages recent exercise scores', () {
    final now = DateTime(2024, 1, 1);
    final exercises = [
      VocalExercise(
        id: 'ex_a',
        name: 'A',
        categoryId: 'cat',
        type: ExerciseType.pitchHighway,
        description: '',
        purpose: '',
        difficulty: ExerciseDifficulty.beginner,
        tags: const [],
        createdAt: now,
      ),
      VocalExercise(
        id: 'ex_b',
        name: 'B',
        categoryId: 'cat',
        type: ExerciseType.pitchHighway,
        description: '',
        purpose: '',
        difficulty: ExerciseDifficulty.beginner,
        tags: const [],
        createdAt: now,
      ),
    ];
    final attempts = [
      ExerciseAttempt(
        id: '1',
        exerciseId: 'ex_a',
        categoryId: 'cat',
        startedAt: now,
        completedAt: now.add(const Duration(minutes: 1)),
        overallScore: 80,
      ),
      ExerciseAttempt(
        id: '2',
        exerciseId: 'ex_a',
        categoryId: 'cat',
        startedAt: now,
        completedAt: now.add(const Duration(minutes: 2)),
        overallScore: 100,
      ),
      ExerciseAttempt(
        id: '3',
        exerciseId: 'ex_b',
        categoryId: 'cat',
        startedAt: now,
        completedAt: now.add(const Duration(minutes: 3)),
        overallScore: 50,
      ),
      ExerciseAttempt(
        id: '4',
        exerciseId: 'ex_b',
        categoryId: 'cat',
        startedAt: now,
        completedAt: now.add(const Duration(minutes: 4)),
        overallScore: 70,
      ),
    ];

    final stats = computeCategoryStats(
      categoryId: 'cat',
      exercises: exercises,
      attempts: attempts,
    );

    expect(stats.score, closeTo(75, 0.001));
    expect(stats.attemptedExercises, 2);
  });

  test('computeOverallStats uses weighted recent average', () {
    final now = DateTime(2024, 1, 1);
    final attempts = [
      ExerciseAttempt(
        id: '1',
        exerciseId: 'ex',
        categoryId: 'cat',
        startedAt: now,
        completedAt: now.add(const Duration(minutes: 1)),
        overallScore: 60,
      ),
      ExerciseAttempt(
        id: '2',
        exerciseId: 'ex',
        categoryId: 'cat',
        startedAt: now,
        completedAt: now.add(const Duration(minutes: 2)),
        overallScore: 80,
      ),
      ExerciseAttempt(
        id: '3',
        exerciseId: 'ex',
        categoryId: 'cat',
        startedAt: now,
        completedAt: now.add(const Duration(minutes: 3)),
        overallScore: 100,
      ),
    ];

    final stats = computeOverallStats(attempts: attempts, recentCount: 10);
    expect(stats.score, closeTo(86.666, 0.01));
    expect(stats.best, 100);
  });
}
