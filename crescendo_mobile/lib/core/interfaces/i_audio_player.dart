import 'dart:async';

enum AudioPlayerState {
  stopped,
  playing,
  paused,
  completed,
  disposed,
}

abstract class IAudioPlayer {
  Future<void> play(String path, {bool isLocal = true, bool isAsset = false});
  Future<void> stop();
  Future<void> pause();
  Future<void> resume();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> dispose();
  
  Stream<Duration> get onPositionChanged;
  Stream<AudioPlayerState> get onPlayerStateChanged;
  Stream<void> get onPlayerComplete;
  
  Future<Duration?> getDuration();
  Future<Duration?> getPosition();
}
