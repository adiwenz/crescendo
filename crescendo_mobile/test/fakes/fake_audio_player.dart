import 'dart:async';
import 'package:crescendo_mobile/core/interfaces/i_audio_player.dart';

class FakeAudioPlayer implements IAudioPlayer {
  AudioPlayerState _state = AudioPlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = const Duration(minutes: 1);
  final _stateController = StreamController<AudioPlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _completeController = StreamController<void>.broadcast();

  // Test helpers
  void setDuration(Duration d) => _duration = d;
  void simulateComplete() {
    _state = AudioPlayerState.completed;
    _stateController.add(_state);
    _completeController.add(null);
  }
  void simulatePosition(Duration p) {
    _position = p;
    _positionController.add(p);
  }

  @override
  Future<void> dispose() async {
    _state = AudioPlayerState.disposed;
    await _stateController.close();
    await _positionController.close();
    await _completeController.close();
  }

  @override
  Future<Duration?> getDuration() async => _duration;

  @override
  Future<Duration?> getPosition() async => _position;

  @override
  Stream<void> get onPlayerComplete => _completeController.stream;

  @override
  Stream<AudioPlayerState> get onPlayerStateChanged => _stateController.stream;

  @override
  Stream<Duration> get onPositionChanged => _positionController.stream;

  @override
  Future<void> pause() async {
    _state = AudioPlayerState.paused;
    _stateController.add(_state);
  }

  @override
  Future<void> play(String path, {bool isLocal = true, bool isAsset = false}) async {
    _state = AudioPlayerState.playing;
    _stateController.add(_state);
  }

  @override
  Future<void> resume() async {
     _state = AudioPlayerState.playing;
    _stateController.add(_state);
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    _positionController.add(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    // no-op
  }

  @override
  Future<void> stop() async {
     _state = AudioPlayerState.stopped;
    _stateController.add(_state);
    _position = Duration.zero;
    _positionController.add(_position);
  }
}
