import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_mobile/services/attempt_repository.dart';
import 'package:crescendo_mobile/services/progress_service.dart';
import 'package:crescendo_mobile/services/simple_progress_repository.dart';
import 'package:crescendo_mobile/models/exercise_attempt.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Progress summary reflects new attempt', () async {
    final attempts = AttemptRepository.instance;
    await attempts.refresh(); // ensure clean load
    final progressService = ProgressService();
    final repo = SimpleProgressRepository();

    final now = DateTime.now();
    final attempt = progressService.buildAttempt(
      exerciseId: 'warmup_test',
      categoryId: 'warmup',
      startedAt: now.subtract(const Duration(minutes: 1)),
      completedAt: now,
      overallScore: 90,
    );
    await progressService.saveAttempt(attempt);
    await attempts.ensureLoaded();
    final summary = await repo.buildSummary();
    expect(summary.totalCompleted >= 1, true);
  });
}
