import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';
import 'dart:io' show Platform;

import 'ui/app.dart';
import 'state/library_store.dart';
import 'services/exercise_cache_service.dart';
import 'services/audio_session_service.dart';
import 'services/storage/db.dart';

import 'core/locator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[DB_TRACE] App Start');

  setupLocator(); // Initialize dependency injection (Real implementations)


  // Check for wireless debugging (iOS only) and log warnings
  if (Platform.isIOS && kDebugMode) {
    _checkWirelessDebugging();
  }

  // Initialize audio session with stable configuration (iOS only)
  await AudioSessionService.init();
  await AudioSessionService.applyExerciseSession(tag: 'boot');

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Preload library completion state.
  await libraryStore.load();

  // Pre-generate exercise cache for current range (if set)
  // This allows exercises to start instantly without generation delay
  ExerciseCacheService.instance.loadCache();

  // Pre-warm database to avoid lazy loading jank on first navigation
  await AppDatabase().database;
  
  runApp(const CrescendoApp());
}

/// Check if device might be using wireless debugging and warn.
/// Note: Flutter doesn't expose a direct API to detect wireless debugging,
/// but we can log instructions to help ensure wired-only debugging.
void _checkWirelessDebugging() {
  if (kDebugMode) {
    debugPrint('[Boot] WIRELESS DEBUG CHECK: Ensure device is connected via USB cable.');
    debugPrint('[Boot] In Xcode: Window > Devices and Simulators > Select device > Uncheck "Connect via network"');
    debugPrint('[Boot] On device: Settings > Developer > Network > Disable "Connect via network"');
    debugPrint('[Boot] If you see slow VM attach times, verify wireless debugging is disabled.');
  }
}
