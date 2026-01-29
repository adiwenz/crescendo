import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// High-accuracy clock abstraction driven by the actual [AudioPlayer] hardware clock.
/// This prevents visual "drift" by ensuring the UI position matches the sound buffer.
class AudioClock {
  final AudioPlayer player;
  
  final _positionController = StreamController<double>.broadcast();
  StreamSubscription? _posSub;
  StreamSubscription? _stateSub;
  
  /// Current playback position in seconds.
  double _currentSec = 0;
  
  /// Whether the audio hardware has actually started emitting sound.
  bool _audioStarted = false;

  AudioClock(this.player) {
    // Listen to native player position updates
    _posSub = player.onPositionChanged.listen((pos) {
      final sec = pos.inMicroseconds / 1e6;
      _currentSec = sec;
      if (!_audioStarted && sec > 0) {
        _audioStarted = true;
      }
      _positionController.add(sec);
    });

    // Listen to state changes to reset started flag
    _stateSub = player.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.stopped || state == PlayerState.completed) {
        _audioStarted = false;
        _currentSec = 0;
        _positionController.add(0);
      }
    });
  }

  /// Stream of current position in seconds.
  Stream<double> get positionStream => _positionController.stream;

  /// Current position in seconds.
  double get nowSeconds => _currentSec;

  /// Returns true ONLY after the audio engine has confirmed playback has begun.
  bool get audioStarted => _audioStarted;

  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
    _positionController.close();
  }
}
