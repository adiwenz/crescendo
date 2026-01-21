import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';
import 'dart:io' show Platform;

import 'ui/app.dart';
import 'state/library_store.dart';
import 'services/exercise_cache_service.dart';
import 'services/audio_route_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Check for wireless debugging (iOS only) and log warnings
  if (Platform.isIOS && kDebugMode) {
    _checkWirelessDebugging();
  }

  final session = await AudioSession.instance;
  await session.configure(
    AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.mixWithOthers |
          AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.measurement, // Better for pitch detection than voiceChat
      // Android fields ignored on iOS:
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
      androidWillPauseWhenDucked: false,
      // Note: PreferredIOBufferDuration is set via AVAudioSession.setPreferredIOBufferDuration
      // The record package should handle this, but we use smaller buffers in RecordingService
    ),
  );

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Preload library completion state.
  await libraryStore.load();

  // Pre-generate exercise cache for current range (if set)
  // This allows exercises to start instantly without generation delay
  ExerciseCacheService.instance.loadCache();

  // Initialize audio route service (uses flutter_audio_output)
  // This is the single source of truth for audio route detection
  await AudioRouteService().initialize();

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
