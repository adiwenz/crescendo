import 'package:shared_preferences/shared_preferences.dart';

class RangeStore {
  static const _lowestKey = 'range_lowest_midi';
  static const _highestKey = 'range_highest_midi';

  Future<void> saveRange({required int lowestMidi, required int highestMidi}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lowestKey, lowestMidi);
    await prefs.setInt(_highestKey, highestMidi);
  }

  Future<int?> getLowestMidi() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lowestKey);
  }

  Future<int?> getHighestMidi() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_highestKey);
  }

  Future<(int?, int?)> getRange() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_lowestKey), prefs.getInt(_highestKey));
  }
}
