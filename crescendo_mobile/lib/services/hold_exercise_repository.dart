import 'package:shared_preferences/shared_preferences.dart';

import '../models/hold_exercise_result.dart';

class HoldExerciseRepository {
  static const _key = 'hold_exercise_results';

  Future<List<HoldExerciseResult>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      return HoldExerciseResult.listFromJson(raw);
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<HoldExerciseResult> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, HoldExerciseResult.listToJson(list));
  }

  Future<void> add(HoldExerciseResult r) async {
    final list = await load();
    list.add(r);
    await save(list);
  }
}
