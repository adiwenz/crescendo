import 'package:shared_preferences/shared_preferences.dart';

class ExerciseRecentRepository {
  static const _key = 'recent_exercises';
  static const _limit = 6;

  Future<List<String>> loadRecentIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key);
    return list ?? const [];
  }

  Future<void> addRecent(String exerciseId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await loadRecentIds();
    final updated = <String>[
      exerciseId,
      ...current.where((id) => id != exerciseId),
    ];
    if (updated.length > _limit) {
      updated.removeRange(_limit, updated.length);
    }
    await prefs.setStringList(_key, updated);
  }
}
