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
  double duration = 0.0; // Accumulated interval-based duration
  final List<double> cents;
  final List<double> times;

  _RunStats()
      : cents = [],
        times = [];

  void addFrame(double centsValue, double timeValue) {
    cents.add(centsValue);
    times.add(timeValue);
  }

  void addDuration(double dt) {
    duration += dt;
  }
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

  // Calculate median hop for gap detection
  final deltas = <double>[];
  for (var i = 1; i < windowFrames.length; i++) {
    final d = windowFrames[i].time - windowFrames[i - 1].time;
    if (d > 0) deltas.add(d);
  }
  final medianHop = deltas.isNotEmpty ? _median(deltas) : 0.0;
  final gapBreak = medianHop > 0 ? medianHop * 2.1 : double.infinity;

  _RunStats? best;
  _RunStats? current;
  double totalOnPitchDuration = 0.0;

  for (var i = 0; i < windowFrames.length; i++) {
    final f = windowFrames[i];
    final hz = f.hz;
    final voiced = hz != null && hz > 0;
    final cents = voiced ? hzToCents(hz!, targetHz) : double.nan;
    final onPitch = voiced && cents.abs() <= centsThreshold && cents.isFinite;

    // Check gap to previous frame if we have a current run
    bool gapTooLarge = false;
    if (current != null && i > 0) {
      final gap = f.time - windowFrames[i - 1].time;
      gapTooLarge = gap > gapBreak;
    }

    if (onPitch && !gapTooLarge) {
      // Start new run if needed
      current ??= _RunStats();
      
      // Add this frame's cents and time to the run
      current.addFrame(cents, f.time - noteStart);
      
      // Calculate duration contribution: time until next frame (or noteEnd)
      // Only contribute if next frame continues the run OR this is the last frame
      double intervalDuration = 0.0;
      
      if (i + 1 < windowFrames.length) {
        final nextFrame = windowFrames[i + 1];
        final nextHz = nextFrame.hz;
        final nextVoiced = nextHz != null && nextHz > 0;
        final nextCents = nextVoiced ? hzToCents(nextHz!, targetHz) : double.nan;
        final nextOnPitch = nextVoiced && nextCents.abs() <= centsThreshold && nextCents.isFinite;
        final nextGap = nextFrame.time - f.time;
        final nextGapTooLarge = nextGap > gapBreak;
        
        if (nextOnPitch && !nextGapTooLarge) {
          // Next frame continues the run - contribute time up to next frame
          intervalDuration = math.max(0.0, math.min(nextFrame.time, noteEnd) - f.time);
        }
        // else: next frame breaks the run - don't contribute duration
      } else {
        // This is the last frame - contribute time until noteEnd
        intervalDuration = math.max(0.0, noteEnd - f.time);
      }
      
      current.addDuration(intervalDuration);
      totalOnPitchDuration += intervalDuration;
    } else {
      // Break current run
      if (current != null) {
        best = _pickBest(best, current);
        current = null;
      }
    }
  }
  
  // Finalize any remaining run
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

  final stddev = best.cents.isNotEmpty ? _stdDev(best.cents) : null;
  final slope = best.cents.length >= 2 ? _slope(best.times, best.cents) : null;

  return HoldMetrics(
    maxContinuousOnPitchSec: best.duration,
    stabilityCentsStdDev: stddev,
    holdPercent: (totalOnPitchDuration / noteDuration).clamp(0.0, 1.0),
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
