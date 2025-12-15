import 'dart:math' as math;

class LoudnessMeter {
  final int windowSize;
  final double alpha; // smoothing factor for EMA
  double _smoothed = 0;
  final List<double> _window = [];

  LoudnessMeter({this.windowSize = 2048, this.alpha = 0.25});

  /// Add a PCM buffer of floats in [-1,1]. Returns the smoothed RMS.
  double addSamples(List<double> samples) {
    for (final s in samples) {
      _window.add(s);
      if (_window.length > windowSize) {
        _window.removeAt(0);
      }
    }
    if (_window.isEmpty) return _smoothed;
    var sum = 0.0;
    for (final s in _window) {
      sum += s * s;
    }
    final rms = math.sqrt(sum / _window.length);
    _smoothed = _smoothed == 0 ? rms : alpha * rms + (1 - alpha) * _smoothed;
    return _smoothed;
  }
}
