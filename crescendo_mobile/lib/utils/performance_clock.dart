class PerformanceClock {
  final Stopwatch _stopwatch = Stopwatch();
  double _offsetSec = 0;
  double _latencySec = 0;
  double _pausedAtSec = 0;
  bool _paused = false;
  bool _freezeUntilAudio = false;
  bool _useAudioPosition = true;

  double? _lastAudioSec;
  double? _lastAudioMonotonicSec;
  double? Function()? _audioPositionProviderSec;

  void setAudioPositionProvider(double? Function()? provider) {
    _audioPositionProviderSec = provider;
  }

  void setUseAudioPosition(bool enabled) {
    _useAudioPosition = enabled;
  }

  void setLatencyCompensationMs(double ms) {
    _latencySec = ms / 1000.0;
  }

  void start({double offsetSec = 0, bool freezeUntilAudio = false}) {
    _offsetSec = offsetSec;
    _paused = false;
    _pausedAtSec = 0;
    _freezeUntilAudio = freezeUntilAudio;
    _lastAudioSec = null;
    _lastAudioMonotonicSec = null;
    _stopwatch
      ..reset()
      ..start();
  }

  void pause() {
    if (_paused) return;
    _pausedAtSec = nowSeconds();
    _paused = true;
    _stopwatch.stop();
  }

  void resume() {
    if (!_paused) return;
    final current = _pausedAtSec;
    _paused = false;
    _offsetSec = current - _stopwatch.elapsedMicroseconds / 1e6 - _latencySec;
    _stopwatch.start();
  }

  double nowSeconds() {
    if (_paused) return _pausedAtSec;
    final audioPos = _useAudioPosition ? _audioPositionProviderSec?.call() : null;
    if (audioPos != null) {
      _lastAudioSec = audioPos;
      _lastAudioMonotonicSec = _stopwatch.elapsedMicroseconds / 1e6;
      _freezeUntilAudio = false;
      return audioPos + _offsetSec + _latencySec;
    }
    if (_freezeUntilAudio && _lastAudioSec == null) {
      return _offsetSec + _latencySec;
    }
    final base = _stopwatch.elapsedMicroseconds / 1e6;
    if (_lastAudioSec != null && _lastAudioMonotonicSec != null) {
      final drift = base - _lastAudioMonotonicSec!;
      return _lastAudioSec! + drift + _offsetSec + _latencySec;
    }
    return base + _offsetSec + _latencySec;
  }

  double get latencySeconds => _latencySec;
}
