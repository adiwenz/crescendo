import 'dart:async';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:crescendo_mobile/core/interfaces/i_audio_player.dart';

class RealAudioPlayer implements IAudioPlayer {
  final ap.AudioPlayer _player;

  RealAudioPlayer([ap.AudioPlayer? player]) : _player = player ?? ap.AudioPlayer();

  @override
  Future<void> dispose() => _player.dispose();

  @override
  Future<Duration?> getDuration() => _player.getDuration();

  @override
  Future<Duration?> getPosition() => _player.getCurrentPosition();

  @override
  Stream<void> get onPlayerComplete => _player.onPlayerComplete;

  @override
  // Map internal state enum if needed, or better yet, map ap.PlayerState to our Enum
  Stream<AudioPlayerState> get onPlayerStateChanged => _player.onPlayerStateChanged.map(_mapState);

  @override
  Stream<Duration> get onPositionChanged => _player.onPositionChanged;

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> play(String path, {bool isLocal = true, bool isAsset = false}) {
    ap.Source source;
    if (isAsset) {
      source = ap.AssetSource(path.replaceFirst('assets/', '')); // AudioPlayers impl assumes assets/ prefix handling or removal?
      // AudioPlayers AssetSource: "The path to the asset, relative to the assets folder."
      // So if path is "audio/piano/60.wav", AssetSource("audio/piano/60.wav") looks in "assets/audio/piano/60.wav" usually?
      // Let's verify expectations. PianoSampleService passes "audio/piano/$fileName".
      // Previous code used `AssetSource('audio/piano/$fileName')`.
      // So path is correct for AssetSource.
    } else if (isLocal) {
      source = ap.DeviceFileSource(path);
    } else {
      source = ap.UrlSource(path);
    }
    return _player.play(source);
  }

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> stop() => _player.stop();
  
  // Helper to map states
  AudioPlayerState _mapState(ap.PlayerState state) {
    switch (state) {
      case ap.PlayerState.stopped: return AudioPlayerState.stopped;
      case ap.PlayerState.playing: return AudioPlayerState.playing;
      case ap.PlayerState.paused: return AudioPlayerState.paused;
      case ap.PlayerState.completed: return AudioPlayerState.completed;
      case ap.PlayerState.disposed: return AudioPlayerState.disposed;
    }
  }
}
