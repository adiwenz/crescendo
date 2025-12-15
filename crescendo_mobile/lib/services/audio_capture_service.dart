import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:mic_stream/mic_stream.dart';
import 'package:permission_handler/permission_handler.dart';

class RecordingService {
  final int sampleRate;
  final int frameSize;
  final int hopSize;
  StreamSubscription<dynamic>? _sub;
  final _samples = <double>[];
  final _buffer = <double>[];
  double _streamTime = 0;

  // Buffer-boundary click reduction.
  static const int _joinFadeSamples = 32; // ~0.7ms @ 44.1k
  static const double _joinJumpThreshold = 0.04; // in [-1,1] float domain

  RecordingService(
      {this.sampleRate = 44100, this.frameSize = 2048, this.hopSize = 256});

  Future<void> start() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      throw StateError('Microphone permission not granted');
    }
    try {
      final rawStream = await MicStream.microphone(
          sampleRate: sampleRate,
          audioSource: AudioSource.DEFAULT,
          channelConfig: ChannelConfig.CHANNEL_IN_MONO,
          audioFormat: AudioFormat.ENCODING_PCM_16BIT);
      final stream = rawStream.transform(MicStream.toSampleStream);
      _sub = stream.listen((sample) {
        final buffer = <double>[];
        if (sample is num) {
          buffer.add(sample.toDouble() / 32768.0);
        } else if (sample is List) {
          for (final s in sample) {
            if (s is num) {
              buffer.add(s.toDouble() / 32768.0);
            }
          }
        }
        if (buffer.isEmpty) return;

        _appendWithBoundarySmoothing(buffer);

        _streamTime += buffer.length / sampleRate;
      }, onError: (e) {
        // Handle error
      }, onDone: () {
        // Handle done
      });
    } catch (e) {
      throw StateError('Failed to start microphone stream: $e');
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _samples.clear();
    _buffer.clear();
    _streamTime = 0;
  }

  void _appendWithBoundarySmoothing(List<double> buffer) {
    if (buffer.isEmpty) return;

    // If we already have samples, check for a discontinuity between the last
    // sample we recorded and the first sample of the incoming buffer.
    if (_samples.isNotEmpty) {
      final last = _samples.last;
      final first = buffer.first;
      final jump = (first - last).abs();

      if (jump > _joinJumpThreshold && jump.isFinite) {
        // Insert a very short ramp to bridge the discontinuity.
        // This removes the time-domain step that produces an audible click.
        final n = _joinFadeSamples;
        for (var i = 1; i <= n; i++) {
          final t = i / (n + 1);
          final v = last + (first - last) * t;
          _samples.add(v);
          _buffer.add(v);
        }
      }
    }

    _samples.addAll(buffer);
    _buffer.addAll(buffer);
  }
}
