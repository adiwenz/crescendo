import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/app.dart';
import 'state/library_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final session = await AudioSession.instance;
  await session.configure(
    const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.voiceChat,
    ),
  );

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Preload library completion state.
  await libraryStore.load();

  runApp(const CrescendoApp());
}
