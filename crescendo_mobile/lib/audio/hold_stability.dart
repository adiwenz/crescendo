import 'dart:math' as math;

import '../models/pitch_frame.dart';

double hzToCents(double measuredHz, double targetHz) {
  if (measuredHz <= 0 || targetHz <= 0) return double.nan;
  return 1200 * (math.log(measuredHz / targetHz) / math.ln2);
}

class HoldMetrics {
  final double maxContinuousOnPitchSec;
  final double? stabilityCentsStdDev;
  final double holdPercent;
  final double? driftCentsPerSec;

  const HoldMetrics({
    required this.maxContinuousOnPitchSec,
    required this.stabilityCentsStdDev,
    required this.holdPercent,
    required this.driftCentsPerSec,
  });
}

class _RunStats {
  final double start;
  double end;
  final List<double> cents;
  final List<double> times;

  _RunStats({required this.start})
      : end = start,
        cents = [],
        times = [];

  double get duration => math.max(0.0, end - start);
}

HoldMetrics computeHoldMetrics({
  required List<PitchFrame> frames,
  required double noteStart,
  required double noteEnd,
  required double targetHz,
  double centsThreshold = 25,
}) {
  if (noteEnd <= noteStart || frames.isEmpty || targetHz <= 0) {
    return const HoldMetrics(
      maxContinuousOnPitchSec: 0,
      stabilityCentsStdDev: null,
      holdPercent: 0,
      driftCentsPerSec: null,
    );
  }

  final windowFrames = frames
      .where((f) => f.time >= noteStart && f.time <= noteEnd)
      .toList()
    ..sort((a, b) => a.time.compareTo(b.time));

  if (windowFrames.length < 2) {
    return const HoldMetrics(
      maxContinuousOnPitchSec: 0,
      stabilityCentsStdDev: null,
      holdPercent: 0,
      driftCentsPerSec: null,
    );
  }

  final deltas = <double>[];
  for (var i = 1; i < windowFrames.length; i++) {
    final d = windowFrames[i].time - windowFrames[i - 1].time;
    if (d > 0) deltas.add(d);
  }
  final medianHop = deltas.isNotEmpty ? _median(deltas) : 0.0;
  final gapBreak = medianHop > 0 ? medianHop * 2.1 : double.infinity;

  _RunStats? best;
  _RunStats? current;

  for (var i = 0; i < windowFrames.length; i++) {
    final f = windowFrames[i];
    final hz = f.hz;
    final voiced = hz != null && hz > 0;
    final cents = voiced ? hzToCents(hz!, targetHz) : double.nan;
    final onPitch = voiced && cents.abs() <= centsThreshold && cents.isFinite;

    double gap = 0;
    if (current != null) {
      gap = f.time - current.end;
    }

    final gapTooLarge = gap > gapBreak;

    if (onPitch && !gapTooLarge) {
      current ??= _RunStats(start: f.time);
      current.end = f.time;
      current.cents.add(cents);
      current.times.add(f.time - noteStart);
    } else {
      if (current != null) {
        best = _pickBest(best, current);
        current = null;
      }
    }
  }
  if (current != null) {
    best = _pickBest(best, current);
  }

  final noteDuration = (noteEnd - noteStart).abs();
  if (best == null || best.duration <= 0) {
    return HoldMetrics(
      maxContinuousOnPitchSec: 0,
      stabilityCentsStdDev: null,
      holdPercent: 0,
      driftCentsPerSec: null,
    );
  }

  final stddev =
      best.cents.isNotEmpty ? _stdDev(best.cents) : null;
  final slope = best.cents.length >= 2 ? _slope(best.times, best.cents) : null;

  final hold = best.duration;
  return HoldMetrics(
    maxContinuousOnPitchSec: hold,
    stabilityCentsStdDev: stddev,
    holdPercent: (hold / noteDuration).clamp(0.0, 1.0),
    driftCentsPerSec: slope,
  );
}

_RunStats? _pickBest(_RunStats? a, _RunStats b) {
  if (a == null) return b;
  return b.duration > a.duration ? b : a;
}

double _median(List<double> xs) {
  final sorted = List<double>.from(xs)..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

double _stdDev(List<double> xs) {
  if (xs.isEmpty) return double.nan;
  final mean = xs.reduce((a, b) => a + b) / xs.length;
  var sumSq = 0.0;
  for (final x in xs) {
    final d = x - mean;
    sumSq += d * d;
  }
  return math.sqrt(sumSq / xs.length);
}

double _slope(List<double> t, List<double> y) {
  if (t.length != y.length || t.length < 2) return double.nan;
  final n = t.length;
  final meanT = t.reduce((a, b) => a + b) / n;
  final meanY = y.reduce((a, b) => a + b) / n;
  double num = 0;
  double den = 0;
  for (var i = 0; i < n; i++) {
    final dt = t[i] - meanT;
    num += dt * (y[i] - meanY);
    den += dt * dt;
  }
  if (den == 0) return double.nan;
  return num / den;
}
