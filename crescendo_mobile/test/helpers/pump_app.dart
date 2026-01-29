import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_mobile/core/locator.dart';
import 'package:crescendo_mobile/core/interfaces/i_audio_player.dart';
import 'package:crescendo_mobile/core/interfaces/i_recorder.dart';
import 'package:crescendo_mobile/core/interfaces/i_audio_session.dart';
import 'package:crescendo_mobile/core/interfaces/i_headset_detector.dart';
import 'package:crescendo_mobile/core/interfaces/i_clock.dart';
import 'package:crescendo_mobile/core/interfaces/i_file_system.dart';
import 'package:crescendo_mobile/core/interfaces/i_preferences.dart';
import 'package:crescendo_mobile/core/interfaces/i_pitch_detector.dart';
import 'package:crescendo_mobile/core/interfaces/i_midi_synth.dart';
import 'package:crescendo_mobile/core/interfaces/i_take_repository.dart';
import '../fakes/fake_audio_player.dart';
import '../fakes/fake_recorder.dart';
import '../fakes/fake_audio_session.dart';
import '../fakes/fake_headset_detector.dart';
import '../fakes/fake_clock.dart';
import '../fakes/fake_file_system.dart';
import '../fakes/fake_preferences.dart';
import '../fakes/fake_pitch_detector.dart';
import '../fakes/fake_midi_synth.dart';
import '../fakes/fake_take_repository.dart';

/// Helper to pump widgets with injected fakes.
/// Provides sensible defaults for all dependencies.
extension PumpApp on WidgetTester {
  Future<void> pumpApp(
    Widget widget, {
    IAudioPlayer? audioPlayer,
    IRecorder? recorder,
    IAudioSession? audioSession,
    IHeadsetDetector? headsetDetector,
    IClock? clock,
    IFileSystem? fileSystem,
    IPreferences? preferences,
    IPitchDetector? pitchDetector,
    IMidiSynth? midiSynth,
    ITakeRepository? takeRepository,
  }) async {
    // Setup locator with provided fakes or defaults
    setupTestLocator(
      audioPlayer: audioPlayer ?? FakeAudioPlayer(),
      recorder: recorder ?? FakeRecorder(),
      audioSession: audioSession ?? FakeAudioSession(),
      headsetDetector: headsetDetector ?? FakeHeadsetDetector(),
      clock: clock ?? FakeClock(),
      fileSystem: fileSystem ?? FakeFileSystem(),
      preferences: preferences ?? FakePreferences(),
      pitchDetector: pitchDetector ?? FakePitchDetector(),
      midiSynth: midiSynth ?? FakeMidiSynth(),
      takeRepository: takeRepository ?? FakeTakeRepository(),
    );
    
    await pumpWidget(
      MaterialApp(
        home: widget,
      ),
    );
    await pump();
  }
}
