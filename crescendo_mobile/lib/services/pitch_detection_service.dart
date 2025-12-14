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
  bool _initialized = false;

  PitchDetectionService({
    this.sampleRate = 44100,
    this.frameSize = 2048,
    this.hopSize = 128,
  });

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await _capture.init();
    _initialized = true;
  }

  Future<Stream<PitchFrame>> startStream() async {
    await _ensureInit();
    final controller = StreamController<PitchFrame>();
    final detector = PitchDetector(audioSampleRate: sampleRate.toDouble(), bufferSize: frameSize);
    double time = 0;
    await _capture.start((obj) {
      final buffer = obj as List<double>;
      for (var i = 0; i + frameSize <= buffer.length; i += hopSize) {
        final frame = buffer.sublist(i, i + frameSize);
        final currentTime = time;
        time += hopSize / sampleRate;
        detector.getPitchFromFloatBuffer(frame).then((result) {
          final hzVal = result.pitch;
          final hz = hzVal != null && hzVal > 0 ? hzVal.toDouble() : null;
          final midi = hz != null && hz > 0 ? _hzToMidi(hz) : null;
          controller.add(PitchFrame(time: currentTime, hz: hz, midi: midi));
        }).catchError((err) {
          controller.addError(err);
        });
      }
    }, (e) {
      controller.addError(e);
    }, sampleRate: sampleRate, bufferSize: frameSize);
    return controller.stream;
  }

  Future<void> stopStream() async {
    await _capture.stop();
  }

  Future<List<PitchFrame>> offlineFromSamples(List<double> samples) async {
    final detector = PitchDetector(audioSampleRate: sampleRate.toDouble(), bufferSize: frameSize);
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
