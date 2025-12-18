import 'one_euro_filter.dart';

class PitchBallController {
  final OneEuroFilter _filter;
  double? _prevTime;
  double? _prevMidi;
  double? _lastTime;
  double? _lastMidi;

  PitchBallController({
    double minCutoff = 3.0,
    double beta = 0.6,
    double dCutoff = 1.0,
  }) : _filter = OneEuroFilter(
          minCutoff: minCutoff,
          beta: beta,
          dCutoff: dCutoff,
        );

  void reset() {
    _filter.reset();
    _prevTime = null;
    _prevMidi = null;
    _lastTime = null;
    _lastMidi = null;
  }

  void addSample({
    required double timeSec,
    required double midi,
  }) {
    if (_lastTime != null && timeSec <= _lastTime!) return;
    final filtered = _filter.filter(midi, timeSec);
    _prevTime = _lastTime;
    _prevMidi = _lastMidi;
    _lastTime = timeSec;
    _lastMidi = filtered;
  }

  double? valueAt(double timeSec) {
    final lastTime = _lastTime;
    final lastMidi = _lastMidi;
    if (lastTime == null || lastMidi == null) return null;
    final prevTime = _prevTime;
    final prevMidi = _prevMidi;
    if (prevTime == null || prevMidi == null) return lastMidi;
    final span = lastTime - prevTime;
    if (span <= 0 || span > 0.25) return lastMidi;
    final alpha = ((timeSec - prevTime) / span).clamp(0.0, 1.0);
    return prevMidi + (lastMidi - prevMidi) * alpha;
  }

  double? estimateLagMs(double visualTimeSec) {
    if (_lastTime == null) return null;
    return (visualTimeSec - _lastTime!) * 1000.0;
  }

  double? get lastSampleTimeSec => _lastTime;

  double? get lastSampleMidi => _lastMidi;
}
