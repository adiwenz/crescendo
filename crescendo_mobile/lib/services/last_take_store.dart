import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/last_take.dart';

class LastTakeStore {
  static const _prefix = 'last_take_';
  static const _latestKey = 'last_take_latest';
  final Map<String, LastTake> _cache = {};

  Future<void> saveLastTake(LastTake take) async {
    _cache[take.exerciseId] = take;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefix + take.exerciseId, jsonEncode(take.toJson()));
    await prefs.setString(_latestKey, take.exerciseId);
  }

  Future<LastTake?> getLastTake(String exerciseId) async {
    if (_cache.containsKey(exerciseId)) return _cache[exerciseId];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefix + exerciseId);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final take = LastTake.fromJson(decoded);
    _cache[exerciseId] = take;
    return take;
  }

  Future<LastTake?> getMostRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_latestKey);
    if (id == null || id.isEmpty) return null;
    return getLastTake(id);
  }
}
