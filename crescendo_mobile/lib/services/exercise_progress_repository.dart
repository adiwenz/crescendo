import 'package:shared_preferences/shared_preferences.dart';

import '../models/exercise_take.dart';

class ExerciseProgressRepository {
  static const _keyPrefix = 'exercise_takes_';

  Future<List<ExerciseTake>> loadTakes(String exerciseId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_keyPrefix$exerciseId');
    if (raw == null) return [];
    try {
      return ExerciseTake.listFromJson(raw);
    } catch (_) {
      return [];
    }
  }

  Future<void> addTake(ExerciseTake take) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await loadTakes(take.exerciseId);
    list.add(take);
    await prefs.setString('$_keyPrefix${take.exerciseId}', ExerciseTake.listToJson(list));
    // simple debug logging
    // ignore: avoid_print
    print('[progress] Saved take ${take.id} for ${take.exerciseId} total now: ${list.length}');
  }

  Future<Map<String, List<ExerciseTake>>> loadAllTakes() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_keyPrefix));
    final Map<String, List<ExerciseTake>> all = {};
    for (final k in keys) {
      final raw = prefs.getString(k);
      if (raw == null) continue;
      try {
        final id = k.replaceFirst(_keyPrefix, '');
        all[id] = ExerciseTake.listFromJson(raw);
      } catch (_) {}
    }
    return all;
  }
}
