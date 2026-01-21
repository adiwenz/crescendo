import 'package:shared_preferences/shared_preferences.dart';
import 'exercise_cache_service.dart';
import 'reference_audio_cache_service.dart';

class RangeStore {
  static const _lowestKey = 'range_lowest_midi';
  static const _highestKey = 'range_highest_midi';

  Future<void> saveRange({
    required int lowestMidi,
    required int highestMidi,
    void Function(int current, int total, String exerciseId)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lowestKey, lowestMidi);
    await prefs.setInt(_highestKey, highestMidi);
    
    // Trigger cache regeneration when range changes
    await ExerciseCacheService.instance.generateCache(
      lowestMidi: lowestMidi,
      highestMidi: highestMidi,
    );
    
    // Generate reference audio cache
    await ReferenceAudioCacheService.instance.generateCacheForRange(
      lowestMidi: lowestMidi,
      highestMidi: highestMidi,
      onProgress: onProgress,
      shouldCancel: shouldCancel,
    );
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

  Future<void> clearRange() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lowestKey);
    await prefs.remove(_highestKey);
  }
}
