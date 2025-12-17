import 'package:flutter/material.dart';

class AppState {
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;
  AppState._internal();

  final ValueNotifier<int> takesVersion = ValueNotifier(0);
}
