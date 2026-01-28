import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:crescendo_mobile/core/interfaces/i_audio_session.dart';

class FakeAudioSession implements IAudioSession {
  bool _isActive = false;
  AudioSessionConfiguration? _config;
  final List<bool> setActiveCalls = [];
  
  final _interruptionController = StreamController<AudioSessionInterruptionEvent>.broadcast();
  final _noisyController = StreamController<void>.broadcast();
  final _devicesController = StreamController<AudioSessionDevicesChangedEvent>.broadcast();

  bool get isActive => _isActive;
  AudioSessionConfiguration? get config => _config;

  @override
  Stream<void> get becomingNoisyEventStream => _noisyController.stream;

  @override
  Future<void> configure(AudioSessionConfiguration configuration) async {
    _config = configuration;
  }

  @override
  Stream<AudioSessionDevicesChangedEvent> get devicesChangedEventStream => _devicesController.stream;

  @override
  Stream<AudioSessionInterruptionEvent> get interruptionEventStream => _interruptionController.stream;

  @override
  Future<bool> setActive(bool active, {bool notifyOthers = true}) async {
    _isActive = active;
    setActiveCalls.add(active);
    return true;
  }
  
  // Test helpers
  void emitInterruption(AudioSessionInterruptionEvent event) => _interruptionController.add(event);
  void emitNoisy() => _noisyController.add(null);
}
