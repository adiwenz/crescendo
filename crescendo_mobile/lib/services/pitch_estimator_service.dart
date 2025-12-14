import 'dart:async';
import 'dart:math' as math;

import 'package:pitch_detector_dart/pitch_detector.dart';

import '../models/pitch_frame.dart';
import 'audio_capture_service.dart';

class PitchEstimatorService {
  final int sampleRate;
  final int frameSize;
  final int hopSize;
  final double rmsGate;
  final PitchDetector _detector;

  PitchEstimatorService({
    this.sampleRate = 44100,
    this.frameSize = 2048,
    this.hopSize = 256,
    this.rmsGate = 0.01,
  }) : _detector = PitchDetector(audioSampleRate: sampleRate.toDouble(), bufferSize: frameSize);

  Stream<PitchFrame> estimate(Stream<AudioFrame> frames) async* {
    double? lastHz;
    double alpha = 0.3;
    await for (final f in frames) {
      if (f.rms < rmsGate) {
        yield PitchFrame(time: f.timestampSec, hz: null, midi: null, centsError: null);
        continue;
      }
      final result = await _detector.getPitchFromFloatBuffer(f.samples);
      final hz = (result.pitch ?? 0) > 0 ? result.pitch!.toDouble() : null;
      double? smoothed = hz;
      if (hz != null && lastHz != null) {
        smoothed = alpha * hz + (1 - alpha) * lastHz;
      }
      if (hz != null) lastHz = smoothed;
      final midi = smoothed != null ? hzToMidi(smoothed) : null;
      yield PitchFrame(time: f.timestampSec, hz: smoothed, midi: midi, centsError: null);
    }
  }

  static double hzToMidi(double hz) => 69 + 12 * math.log(hz / 440) / math.ln2;
}
