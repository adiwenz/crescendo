import 'package:flutter/material.dart';

import '../models/warmup.dart';

class AppState {
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;
  AppState._internal();

  final ValueNotifier<WarmupDefinition> selectedWarmup = ValueNotifier(WarmupsLibrary.defaults.first);
  List<String> customNotes = [];
}
