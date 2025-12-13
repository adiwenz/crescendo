import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_audio_capture/flutter_audio_capture.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';

import '../models/pitch_frame.dart';
import '../models/warmup.dart';

class PitchDetectionService {
  final _capture = FlutterAudioCapture();
  final int sampleRate;
  final int frameSize;
  final int hopSize;

  PitchDetectionService({
    this.sampleRate = 44100,
    this.frameSize = 2048,
    this.hopSize = 256,
  });

  Future<Stream<PitchFrame>> startStream() async {
    final controller = StreamController<PitchFrame>();
    final detector = PitchDetector(sampleRate: sampleRate, bufferSize: frameSize);
    double time = 0;
    await _capture.start(listener: (obj) {
      final buffer = (obj as List<dynamic>).cast<double>();
      for (var i = 0; i + frameSize <= buffer.length; i += hopSize) {
        final frame = buffer.sublist(i, i + frameSize);
        final pitch = detector.getPitch(frame);
        final hz = pitch[0] > 0 ? pitch[0].toDouble() : null;
        final midi = hz != null && hz > 0 ? _hzToMidi(hz) : null;
        controller.add(PitchFrame(time: time, hz: hz, midi: midi));
        time += hopSize / sampleRate;
      }
    }, onError: (e) {
      controller.addError(e);
    }, sampleRate: sampleRate, bufferSize: frameSize);
    return controller.stream;
  }

  Future<void> stopStream() async {
    await _capture.stop();
  }

  List<PitchFrame> offlineFromSamples(List<double> samples) {
    final detector = PitchDetector(sampleRate: sampleRate, bufferSize: frameSize);
    final frames = <PitchFrame>[];
    double time = 0;
    for (var i = 0; i + frameSize <= samples.length; i += hopSize) {
      final frame = samples.sublist(i, i + frameSize);
      final pitch = detector.getPitch(frame);
      final hz = pitch[0] > 0 ? pitch[0].toDouble() : null;
      final midi = hz != null && hz > 0 ? _hzToMidi(hz) : null;
      frames.add(PitchFrame(time: time, hz: hz, midi: midi));
      time += hopSize / sampleRate;
    }
    return frames;
  }

  double _hzToMidi(double hz) => 69 + 12 * math.log(hz / 440) / math.ln2;
}
