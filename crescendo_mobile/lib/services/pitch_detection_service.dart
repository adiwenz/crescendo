import 'dart:math' as math;

import 'package:pitch_detector_dart/pitch_detector.dart';

import '../models/pitch_frame.dart';
import '../models/warmup.dart';

class PitchDetectionService {
  final int sampleRate;
  final int frameSize;
  final int hopSize;

  PitchDetectionService({
    this.sampleRate = 44100,
    this.frameSize = 1024,
    this.hopSize = 64,
  });

  Future<List<PitchFrame>> offlineFromSamples(List<double> samples) async {
    final detector =
        PitchDetector(audioSampleRate: sampleRate.toDouble(), bufferSize: frameSize);
    final frames = <PitchFrame>[];
    double time = 0;
    for (var i = 0; i + frameSize <= samples.length; i += hopSize) {
      final frame = samples.sublist(i, i + frameSize);
      final result = await detector.getPitchFromFloatBuffer(frame);
      final hzVal = result.pitch;
      final hz = hzVal != null && hzVal > 0 ? hzVal.toDouble() : null;
      final midi = hz != null && hz > 0 ? _hzToMidi(hz) : null;
      frames.add(PitchFrame(time: time, hz: hz, midi: midi));
      time += hopSize / sampleRate;
    }
    return frames;
  }

  double _hzToMidi(double hz) => 69 + 12 * math.log(hz / 440) / math.ln2;
}
