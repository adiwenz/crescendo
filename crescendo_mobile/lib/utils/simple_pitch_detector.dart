import 'dart:math' as math;

class PitchDetectionResult {
  final double? pitch;
  const PitchDetectionResult({this.pitch});
}

/// Lightweight autocorrelation-based pitch detector for mono PCM buffers.
class SimplePitchDetector {
  final int sampleRate;

  SimplePitchDetector(this.sampleRate);

  PitchDetectionResult getPitch(List<double> buffer) {
    if (buffer.isEmpty) return const PitchDetectionResult(pitch: null);
    final minLag = (sampleRate / 1000).round(); // up to ~1 kHz
    final maxLag = (sampleRate / 50).round(); // down to ~50 Hz
    double bestCorr = 0;
    int bestLag = 0;
    for (var lag = minLag; lag <= maxLag && lag < buffer.length; lag++) {
      double corr = 0;
      for (var i = 0; i + lag < buffer.length; i++) {
        corr += buffer[i] * buffer[i + lag];
      }
      if (corr > bestCorr) {
        bestCorr = corr;
        bestLag = lag;
      }
    }
    if (bestLag == 0) return const PitchDetectionResult(pitch: null);
    final freq = sampleRate / bestLag;
    if (!freq.isFinite || freq <= 0) return const PitchDetectionResult(pitch: null);
    return PitchDetectionResult(pitch: freq);
  }
}
