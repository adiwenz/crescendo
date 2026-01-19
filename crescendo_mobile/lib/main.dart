import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/app.dart';
import 'state/library_store.dart';
import 'services/exercise_cache_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(const CrescendoApp());
}
