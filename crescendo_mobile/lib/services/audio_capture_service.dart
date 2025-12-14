import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mic_stream/mic_stream.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioFrame {
  final List<double> samples;
  final double timestampSec;
  final double rms;
  AudioFrame(
      {required this.samples, required this.timestampSec, required this.rms});
}

class AudioCaptureService {
  final int sampleRate;
  final int frameSize;
  final int hopSize;
  StreamSubscription<dynamic>? _sub;
  final _buffer = <double>[];
  double _time = 0;
  StreamController<AudioFrame>? _controller;

  AudioCaptureService(
      {this.sampleRate = 44100, this.frameSize = 2048, this.hopSize = 256});

  Future<Stream<AudioFrame>> start() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      throw StateError('Microphone permission not granted');
    }
    final controller = StreamController<AudioFrame>();
    _controller = controller;
    try {
      final rawStream = await MicStream.microphone(
          sampleRate: sampleRate,
          audioSource: AudioSource.DEFAULT,
          channelConfig: ChannelConfig.CHANNEL_IN_MONO,
          audioFormat: AudioFormat.ENCODING_PCM_16BIT);
      final stream = rawStream.transform(MicStream.toSampleStream);
      _sub = stream.listen((sample) {
        if (sample is num) {
          _buffer.add(sample.toDouble() / 32768.0);
        } else if (sample is List) {
          for (final s in sample) {
            if (s is num) {
              _buffer.add(s.toDouble() / 32768.0);
            }
          }
        }
        while (_buffer.length >= frameSize) {
          final frame = _buffer.sublist(0, frameSize);
          _buffer.removeRange(0, hopSize);
          final rms = _computeRms(frame);
          controller
              .add(AudioFrame(samples: frame, timestampSec: _time, rms: rms));
          _time += hopSize / sampleRate;
        }
      }, onError: (e) {
        if (_controller != null && !_controller!.isClosed) {
          _controller!.addError(e);
        }
      }, onDone: () {
        if (_controller != null && !_controller!.isClosed) {
          _controller!.close();
        }
      });
    } catch (e) {
      throw StateError('Failed to start microphone stream: $e');
    }
    controller.onCancel = () async {
      await stop();
    };
    return controller.stream;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _buffer.clear();
    _time = 0;
    await _controller?.close();
    _controller = null;
  }

  double _computeRms(List<double> frame) {
    if (frame.isEmpty) return 0;
    var sum = 0.0;
    for (final v in frame) {
      sum += v * v;
    }
    return math.sqrt(sum / frame.length);
  }
}
