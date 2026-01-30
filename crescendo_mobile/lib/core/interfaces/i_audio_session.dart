import 'dart:async';
import 'package:audio_session/audio_session.dart';

abstract class IAudioSession {
  Future<bool> setActive(bool active);
  Future<void> configure(AudioSessionConfiguration configuration);
  
  // Audio focus event streams for debugging
  Stream<AudioInterruptionEvent> get interruptionEventStream;
  Stream<void> get becomingNoisyEventStream;
}
