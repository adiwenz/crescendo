import 'package:shared_preferences/shared_preferences.dart';

import '../models/pitch_highway_difficulty.dart';

class UnlockResult {
  final bool levelUp;
  final PitchHighwayDifficulty? unlockedDifficulty;

  const UnlockResult({required this.levelUp, this.unlockedDifficulty});
}

class UnlockService {
  static const _unlockPrefix = 'exercise_unlock_';
  static const _bestPrefix = 'exercise_best_';

  Future<int> getMaxUnlocked(String exerciseId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_unlockPrefix$exerciseId') ?? 0;
  }

  Future<void> setMaxUnlocked(String exerciseId, int max) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_unlockPrefix$exerciseId', max.clamp(0, 2));
  }

  Future<void> saveBestScore({
    required String exerciseId,
    required PitchHighwayDifficulty difficulty,
    required int score,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_bestPrefix${exerciseId}_${difficulty.name}';
    final current = prefs.getInt(key) ?? 0;
    if (score > current) {
      await prefs.setInt(key, score);
    }
  }

  Future<UnlockResult> applyResult({
    required String exerciseId,
    required PitchHighwayDifficulty difficulty,
    required int score,
  }) async {
    await saveBestScore(
      exerciseId: exerciseId,
      difficulty: difficulty,
      score: score,
    );
    final currentMax = await getMaxUnlocked(exerciseId);
    final currentIdx = pitchHighwayDifficultyIndex(difficulty);
    if (score >= 90 && currentIdx == currentMax && currentMax < 2) {
      final next = currentMax + 1;
      await setMaxUnlocked(exerciseId, next);
      return UnlockResult(
        levelUp: true,
        unlockedDifficulty: pitchHighwayDifficultyFromIndex(next),
      );
    }
    return const UnlockResult(levelUp: false);
  }
}
