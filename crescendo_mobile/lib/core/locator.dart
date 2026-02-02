import 'package:get_it/get_it.dart';
import 'package:crescendo_mobile/core/interfaces/i_audio_player.dart';
import 'package:crescendo_mobile/core/interfaces/i_recorder.dart';
import 'package:crescendo_mobile/core/interfaces/i_audio_session.dart';
import 'package:crescendo_mobile/core/interfaces/i_clock.dart';
import 'package:crescendo_mobile/core/interfaces/i_file_system.dart';
import 'package:crescendo_mobile/core/interfaces/i_midi_synth.dart';
import 'package:crescendo_mobile/core/interfaces/i_take_repository.dart';
import 'package:crescendo_mobile/core/interfaces/i_preferences.dart';
import 'package:crescendo_mobile/core/wrappers/real_audio_player.dart';
// Import other real implementations... 

import 'package:crescendo_mobile/core/wrappers/real_audio_session.dart';
import 'package:crescendo_mobile/core/wrappers/real_clock.dart';
import 'package:crescendo_mobile/core/wrappers/real_file_system.dart';
import 'package:crescendo_mobile/core/wrappers/real_preferences.dart';
import 'package:crescendo_mobile/core/wrappers/real_recorder.dart';
import 'package:crescendo_mobile/core/wrappers/real_midi_synth.dart';
import 'package:crescendo_mobile/services/storage/take_repository.dart';

// Using GetIt for simplicity as suggested in plan
final locator = GetIt.instance;

void setupLocator() {
  // Register Factories (new instance per call)
  locator.registerFactory<IAudioPlayer>(() => RealAudioPlayer());
  locator.registerFactory<IRecorder>(() => RealRecorder());
  
  // Register Singletons (shared instance)
  locator.registerLazySingleton<IAudioSession>(() => RealAudioSession());
  locator.registerLazySingleton<IClock>(() => RealClock());
  locator.registerLazySingleton<IFileSystem>(() => RealFileSystem());
  locator.registerLazySingleton<IPreferences>(() => RealPreferences());
  locator.registerLazySingleton<IMidiSynth>(() => RealMidiSynth());
  locator.registerLazySingleton<ITakeRepository>(() => TakeRepository());
}

// Helper for test setup
void setupTestLocator({
  IAudioPlayer? audioPlayer,
  IRecorder? recorder,
  IAudioSession? audioSession,
  IClock? clock,
  IFileSystem? fileSystem,
  IPreferences? preferences,
  IMidiSynth? midiSynth,
  ITakeRepository? takeRepository,
}) {
  locator.reset();
  
  // Register provided mocks/fakes or throw if missing in test context (or use lenient defaults)
  // For tests, we usually want explicit fakes.
  
  if (audioPlayer != null) locator.registerFactory<IAudioPlayer>(() => audioPlayer);
  if (recorder != null) locator.registerFactory<IRecorder>(() => recorder);
  if (audioSession != null) locator.registerLazySingleton<IAudioSession>(() => audioSession);
  if (clock != null) locator.registerLazySingleton<IClock>(() => clock);
  if (fileSystem != null) locator.registerLazySingleton<IFileSystem>(() => fileSystem);
  if (preferences != null) locator.registerLazySingleton<IPreferences>(() => preferences);
  if (midiSynth != null) locator.registerLazySingleton<IMidiSynth>(() => midiSynth);
  if (takeRepository != null) locator.registerLazySingleton<ITakeRepository>(() => takeRepository);
}
