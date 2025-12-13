import 'dart:math' as math;

import '../models/metrics.dart';
import '../models/pitch_frame.dart';

class ScoringService {
  Metrics score(List<PitchFrame> frames) {
    final cents = frames
        .map((f) => f.centsError)
        .where((c) => c != null && c!.isFinite)
        .map((c) => c!.abs().toDouble())
        .toList();
    if (cents.isEmpty) {
      return Metrics(score: 0, meanAbsCents: 0, pctWithin20: 0, pctWithin50: 0, validFrames: 0);
    }
    final mean = cents.reduce((a, b) => a + b) / cents.length;
    final pct20 = cents.where((c) => c <= 20).length / cents.length * 100.0;
    final pct50 = cents.where((c) => c <= 50).length / cents.length * 100.0;
    final score = 100.0 * (1 - math.min(mean / 100.0, 1.0));
    return Metrics(
      score: score,
      meanAbsCents: mean,
      pctWithin20: pct20,
      pctWithin50: pct50,
      validFrames: cents.length,
    );
  }
}
