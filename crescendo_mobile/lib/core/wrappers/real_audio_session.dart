import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:crescendo_mobile/core/interfaces/i_audio_session.dart';

class RealAudioSession implements IAudioSession {
  AudioSession? _session;

  Future<AudioSession> _get() async {
    _session ??= await AudioSession.instance;
    return _session!;
  }

  @override
  Future<void> configure(AudioSessionConfiguration configuration) async {
    (await _get()).configure(configuration);
  }

  @override
  Future<bool> setActive(bool active) async {
    return (await _get()).setActive(active);
  }
  
  @override
  Stream<AudioInterruptionEvent> get interruptionEventStream async* {
    yield* (await _get()).interruptionEventStream;
  }
  
  @override
  Stream<void> get becomingNoisyEventStream async* {
    yield* (await _get()).becomingNoisyEventStream;
  }
}
