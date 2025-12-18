import 'dart:math' as math;

class OneEuroFilter {
  final double minCutoff;
  final double beta;
  final double dCutoff;

  double? _lastTime;
  double? _xHat;
  double? _dxHat;

  OneEuroFilter({
    this.minCutoff = 1.8,
    this.beta = 0.25,
    this.dCutoff = 1.0,
  });

  double filter(double x, double t) {
    if (_lastTime == null || _xHat == null || _dxHat == null) {
      _lastTime = t;
      _xHat = x;
      _dxHat = 0;
      return x;
    }
    final dt = (t - _lastTime!).clamp(1e-6, 1.0);
    final dx = (x - _xHat!) / dt;
    final alphaD = _alpha(dt, dCutoff);
    _dxHat = _dxHat! + alphaD * (dx - _dxHat!);
    final cutoff = minCutoff + beta * _dxHat!.abs();
    final alpha = _alpha(dt, cutoff);
    _xHat = _xHat! + alpha * (x - _xHat!);
    _lastTime = t;
    return _xHat!;
  }

  void reset() {
    _lastTime = null;
    _xHat = null;
    _dxHat = null;
  }

  double _alpha(double dt, double cutoff) {
    final tau = 1.0 / (2.0 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }
}
