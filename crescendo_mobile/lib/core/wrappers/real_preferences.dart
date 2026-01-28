import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crescendo_mobile/core/interfaces/i_preferences.dart';

class RealPreferences implements IPreferences {
  SharedPreferences? _prefs;

  Future<SharedPreferences> _get() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  @override
  Future<bool> clear() async => (await _get()).clear();

  @override
  bool? getBool(String key) => _prefs?.getBool(key);

  @override
  double? getDouble(String key) => _prefs?.getDouble(key);

  @override
  int? getInt(String key) => _prefs?.getInt(key);

  @override
  String? getString(String key) => _prefs?.getString(key);

  @override
  List<String>? getStringList(String key) => _prefs?.getStringList(key);

  @override
  Future<bool> remove(String key) async => (await _get()).remove(key);

  @override
  Future<bool> setBool(String key, bool value) async => (await _get()).setBool(key, value);

  @override
  Future<bool> setDouble(String key, double value) async => (await _get()).setDouble(key, value);

  @override
  Future<bool> setInt(String key, int value) async => (await _get()).setInt(key, value);

  @override
  Future<bool> setString(String key, String value) async => (await _get()).setString(key, value);

  @override
  Future<bool> setStringList(String key, List<String> value) async => (await _get()).setStringList(key, value);
}
