import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../audio/wav_util.dart';

class AudioOffsetResult {
  final int offsetSamples;
  final double offsetMs;
  final double confidence;
  final String method;

  AudioOffsetResult({
    required this.offsetSamples,
    required this.offsetMs,
    required this.confidence,
    required this.method,
  });

  @override
  String toString() {
    return 'Offset: $offsetSamples samples (${offsetMs.toStringAsFixed(2)} ms), conf: ${confidence.toStringAsFixed(2)}, method: $method';
  }
}

enum OffsetStrategy {
  chirp,
  crossCorrelation,
  auto,
}

class AudioOffsetEstimator {
  /// Estimates the offset (lag) of the recording relative to the reference.
  /// positive offset => recording is LATE (needs to be shifted left or started earlier)
  /// negative offset => recording is EARLY (reference is late)
  static Future<AudioOffsetResult> estimateOffsetSamples({
    required String recordedPath,
    required String referencePath,
    OffsetStrategy strategy = OffsetStrategy.auto,
    double searchWindowSec = 2.0, // Limit search to first N seconds
  }) async {
    try {
      final recWav = await WavUtil.readPcm16Wav(recordedPath);
      final refWav = await WavUtil.readPcm16Wav(referencePath);

      debugPrint('[AudioOffsetEstimator] Loaded WAVs: Ref=${refWav.sampleRate}Hz, Rec=${recWav.sampleRate}Hz');

      if (recWav.sampleRate != refWav.sampleRate) {
        debugPrint('[AudioOffsetEstimator] Sample rate mismatch! Normalizing logic needed.');
        // For now, assume simple case or fail gracefully
      }

      final sampleRate = recWav.sampleRate;
      final maxFrames = (searchWindowSec * sampleRate).toInt();

      // Extract mono buffers for analysis (limited to window)
      final refFloats = _toMonoFloat(refWav, maxFrames);
      final recFloats = _toMonoFloat(recWav, maxFrames);

      if (strategy == OffsetStrategy.chirp || strategy == OffsetStrategy.auto) {
        // Apply High-Pass Filter to emphasize Ultrasonic Chirp (19kHz)
        // Simple differentiator: y[n] = x[n] - x[n-1]
        // This attenuates low frequencies (noise/voice) and boosts high frequencies.
        final refFiltered = _applyDifferentiation(refFloats);
        final recFiltered = _applyDifferentiation(recFloats);

        // Try chirp/peak detection
        final result = _estimateChirpOffset(refFiltered, recFiltered, sampleRate);
        if (result.confidence > 0.5 || strategy == OffsetStrategy.chirp) {
           return result;
        }
        debugPrint('[AudioOffsetEstimator] Chirp confidence low (${result.confidence}), falling back...');
      }

      // XCorr Fallback
      return _estimateXCorrOffset(refFloats, recFloats, sampleRate);

    } catch (e) {
      debugPrint('[AudioOffsetEstimator] Error calculating offset: $e');
      return AudioOffsetResult(
        offsetSamples: 0,
        offsetMs: 0,
        confidence: 0,
        method: 'error',
      );
    }
  }

  static List<double> _toMonoFloat(WavPcm16 wav, int maxFrames) {
    final frameCount = math.min(wav.data.length ~/ wav.channels, maxFrames);
    final floats = List<double>.filled(frameCount, 0);
    
    for (int i = 0; i < frameCount; i++) {
       double sum = 0;
       for (int c = 0; c < wav.channels; c++) {
         sum += wav.data[i * wav.channels + c];
       }
       // Normalize to -1.0 .. 1.0
       floats[i] = (sum / wav.channels) / 32768.0; 
    }
    return floats;
  }

  static List<double> _applyDifferentiation(List<double> input) {
    if (input.isEmpty) return [];
    final output = List<double>.filled(input.length, 0.0);
    
    // y[0] = x[0]
    output[0] = input[0];
    
    for (int i = 1; i < input.length; i++) {
      output[i] = input[i] - input[i - 1]; // Simple 1st order High pass
    }
    
    return output;
  }

  static AudioOffsetResult _estimateChirpOffset(
    List<double> ref, 
    List<double> rec, 
    int sampleRate
  ) {
    // Simple peak finding: Find index of max absolute amplitude
    int refPeak = _findPeakIndex(ref);
    int recPeak = _findPeakIndex(rec);

    final offset = recPeak - refPeak;
    
    // Heuristic confidence: amplitude of peak vs RMS
    final refConf = _peakConfidence(ref, refPeak);
    final recConf = _peakConfidence(rec, recPeak);
    final confidence = math.min(refConf, recConf);

    return AudioOffsetResult(
      offsetSamples: offset,
      offsetMs: (offset / sampleRate) * 1000.0,
      confidence: confidence,
      method: 'peak',
    );
  }

  static int _findPeakIndex(List<double> signal) {
    if (signal.isEmpty) return 0;
    int maxIdx = 0;
    double maxVal = 0;
    for (int i = 0; i < signal.length; i++) {
      if (signal[i].abs() > maxVal) {
        maxVal = signal[i].abs();
        maxIdx = i;
      }
    }
    return maxIdx;
  }

  static double _peakConfidence(List<double> signal, int peakIdx) {
     if (signal.isEmpty) return 0.0;
     final peakVal = signal[peakIdx].abs();
     if (peakVal < 0.01) return 0.0; // Too quiet
     
     // Calculate RMS of surrounding area (excluding peak slightly) to check contrast
     // Simple: just global RMS
     double sumSq = 0;
    for (final s in signal) {
      sumSq += s * s;
    }
     final rms = math.sqrt(sumSq / signal.length);
     
     if (rms == 0) return 0.0;
     final snr = peakVal / rms;
     // Arbitrary mapping: SNR > 5 is good
     return (snr / 10.0).clamp(0.0, 1.0);
  }

  static AudioOffsetResult _estimateXCorrOffset(
    List<double> ref, 
    List<double> rec, 
    int sampleRate
  ) {
    // Normalized Cross-Correlation
    // We assume the offset is within +/- 0.5s of the start for efficiency (or whatever window passed)
    // ref is the kernel, rec is the search space? Or vice versa.
    // Usually we slide one over the other.
    
    // To be efficient in Dart without FFT:
    // Limit lag search range.
    // If we expect potential lag of +/- 500ms -> +/- 24000 samples @ 48k.
    // That's O(N*M) which is heavy. 
    
    // Optimization: Downsample 4x or 8x for coarse search, then refine?
    // Let's stick to a small lag window around 0 if we assume they start roughly together.
    
    // Let's assume recording starts LATER than reference usually (latency).
    // So lag 0..500ms.
    
    final maxLag = (0.5 * sampleRate).toInt(); 
    final minLag = -(0.1 * sampleRate).toInt(); // Allow small negative lag
    
    int bestLag = 0;
    double maxCorr = -1.0;
    
    // Correlation window size: use enough signal to be robust, e.g. 1 sec or length
    final windowSize = math.min(ref.length, rec.length) - math.max(maxLag.abs(), minLag.abs()) - 1;
    
    if (windowSize <= 0) {
        return AudioOffsetResult(offsetSamples: 0, offsetMs: 0, confidence: 0, method: 'xcorr_fail');
    }

    for (int lag = minLag; lag <= maxLag; lag += 4) { // stride 4 for speed, then refine?
       double dot = 0;
       double refSumSq = 0;
       double recSumSq = 0;
       
       // dot product of ref[i] and rec[i+lag]
       // i ranges over overlap
       for (int i = 0; i < windowSize; i += 4) { // stride subsampling for coarse estimation
          int refIdx = i;
          int recIdx = i + lag;
          
          if (recIdx >= 0 && recIdx < rec.length && refIdx < ref.length) {
             double r = ref[refIdx];
             double s = rec[recIdx];
             dot += r * s;
             refSumSq += r * r;
             recSumSq += s * s;
          }
       }
       
       double denom = math.sqrt(refSumSq * recSumSq);
       if (denom > 0) {
         double corr = dot / denom;
         if (corr > maxCorr) {
           maxCorr = corr;
           bestLag = lag;
         }
       }
    }

    return AudioOffsetResult(
      offsetSamples: bestLag,
      offsetMs: (bestLag / sampleRate) * 1000.0,
      confidence: maxCorr,
      method: 'xcorr_coarse',
    );
  }
}
