import 'package:flutter/services.dart';

class TransportClock {
  static const MethodChannel _channel = MethodChannel('transport_clock');

  Future<bool> ensureStarted() async {
    final result = await _channel.invokeMethod<bool>('ensureStarted');
    return result ?? false;
  }

  Future<double> getSampleRate() async {
    final result = await _channel.invokeMethod<double>('getSampleRate');
    return result ?? 48000.0;
  }

  Future<int?> getCurrentSampleTime() async {
    // Returns int64 from native, which fits in Dart int
    final result = await _channel.invokeMethod<int>('getCurrentSampleTime');
    return result;
  }

  Future<bool> startPlayback({required String path, double seekSeconds = 0.0}) async {
    final result = await _channel.invokeMethod<bool>('startPlayback', {
      'path': path,
      'seekSeconds': seekSeconds,
    });
    return result ?? false;
  }

  Future<String> startRecording({String? dirPath}) async {
    final result = await _channel.invokeMethod<String>('startRecording', {
      'dirPath': dirPath,
    });
    return result ?? '';
  }

  Future<bool> stopRecording() async {
    final result = await _channel.invokeMethod<bool>('stopRecording');
    return result ?? false;
  }

  Future<int?> getRecordStartSampleTime() async {
    return await _channel.invokeMethod<int>('getRecordStartSampleTime');
  }

  Future<int?> getPlaybackStartSampleTime() async {
    return await _channel.invokeMethod<int>('getPlaybackStartSampleTime');
  }

  Future<bool> stopAll() async {
    final result = await _channel.invokeMethod<bool>('stopAll');
    return result ?? false;
  }

  Future<String> mixWithOffset({
    required String referencePath,
    required String vocalPath,
    required int vocalOffsetSamples,
    required String outputPath,
  }) async {
    final result = await _channel.invokeMethod<String>('mixWithOffset', {
      'referencePath': referencePath,
      'vocalPath': vocalPath,
      'vocalOffsetSamples': vocalOffsetSamples,
      'outputPath': outputPath,
    });
    return result ?? '';
  }
}
