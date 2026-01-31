import 'dart:typed_data';
import 'package:flutter/services.dart';

class DuplexCapture {
  final Uint8List pcm16;
  final int numFrames;
  final int sampleRate;
  final int channels;
  final int inputFramePos;
  final int outputFramePos;
  final int timestampNanos;

  DuplexCapture({
    required this.pcm16,
    required this.numFrames,
    required this.sampleRate,
    required this.channels,
    required this.inputFramePos,
    required this.outputFramePos,
    required this.timestampNanos,
  });

  factory DuplexCapture.from(dynamic event) {
    final m = event as Map;
    return DuplexCapture(
      pcm16: m['pcm16'] as Uint8List,
      numFrames: m['numFrames'] as int,
      sampleRate: m['sampleRate'] as int,
      channels: m['channels'] as int,
      inputFramePos: (m['inputFramePos'] as int),
      outputFramePos: (m['outputFramePos'] as int),
      timestampNanos: (m['timestampNanos'] as int),
    );
  }
}

class DuplexAudio {
  static const _methods = MethodChannel('duplex_audio/methods');
  static const _events = EventChannel('duplex_audio/events');

  static Stream<DuplexCapture> get stream =>
      _events.receiveBroadcastStream().map(DuplexCapture.from);

  static Future<void> start({
    required String wavAssetPath,
    int sampleRate = 48000,
    int channels = 1,
    int framesPerCallback = 192,
  }) async {
    await _methods.invokeMethod('start', {
      'wavAssetPath': wavAssetPath,
      'sampleRate': sampleRate,
      'channels': channels,
      'framesPerCallback': framesPerCallback,
    });
  }

  static Future<void> stop() => _methods.invokeMethod('stop');

  static Future<void> setGain(double gain) =>
      _methods.invokeMethod('setGain', {'gain': gain});
}
