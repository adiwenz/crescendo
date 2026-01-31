library one_clock_audio;

import 'package:flutter/services.dart';
import 'src/types.dart';

export 'src/types.dart';

class OneClockAudio {
  static const MethodChannel _m = MethodChannel('one_clock_audio/methods');
  static const EventChannel _e = EventChannel('one_clock_audio/events');

  static Stream<OneClockCapture>? _stream;

  static Stream<OneClockCapture> get captureStream {
    _stream ??= _e.receiveBroadcastStream().map((e) {
      return OneClockCapture.fromMap(e as Map<dynamic, dynamic>);
    });
    return _stream!;
  }

  static Future<bool> start(OneClockStartConfig config) async {
    final result = await _m.invokeMethod('start', config.toMap());
    return result as bool? ?? false;
  }

  static Future<void> stop() => _m.invokeMethod('stop');

  static Future<void> setPlaybackGain(double gain) =>
      _m.invokeMethod('setGain', {'gain': gain});

  // --- Two Track Playback ---
  static Future<bool> loadReference(String path) async {
    return await _m.invokeMethod('loadReference', {'path': path}) ?? false;
  }
  
  static Future<bool> loadVocal(String path) async {
    return await _m.invokeMethod('loadVocal', {'path': path}) ?? false;
  }
  
  static Future<void> setTrackGains({double ref = 1.0, double voc = 1.0}) async {
    await _m.invokeMethod('setTrackGains', {'ref': ref, 'voc': voc});
  }
  
  static Future<void> setVocalOffset(int frames) async {
    await _m.invokeMethod('setVocalOffset', {'frames': frames});
  }
  
  static Future<bool> startPlaybackTwoTrack() async {
    return await _m.invokeMethod('startPlaybackTwoTrack') ?? false;
  }
  
  static Future<NativeSessionSnapshot?> getSessionSnapshot() async {
    final List<dynamic>? res = await _m.invokeMethod('getSessionSnapshot');
    if (res == null) return null;
    return NativeSessionSnapshot.fromList(res.cast<int>());
  }

  // --- Transport-style API (single engine: ref playback + mic record to file) ---
  static Future<bool> ensureStarted() async {
    final result = await _m.invokeMethod<bool>('ensureStarted');
    return result ?? false;
  }

  static Future<double> getSampleRate() async {
    final result = await _m.invokeMethod<double>('getSampleRate');
    return result ?? 48000.0;
  }

  static Future<bool> startPlayback({
    required String referencePath,
    double gain = 1.0,
  }) async {
    final result = await _m.invokeMethod<bool>('startPlayback', {
      'referencePath': referencePath,
      'gain': gain,
    });
    return result ?? false;
  }

  static Future<String> startRecording({required String outputPath}) async {
    final result = await _m.invokeMethod<String>('startRecording', {
      'outputPath': outputPath,
    });
    return result ?? '';
  }

  static Future<void> stopRecording() => _m.invokeMethod('stopRecording');

  static Future<void> stopAll() => _m.invokeMethod('stopAll');

  static Future<int?> getPlaybackStartSampleTime() async {
    return await _m.invokeMethod<int>('getPlaybackStartSampleTime');
  }

  static Future<int?> getRecordStartSampleTime() async {
    return await _m.invokeMethod<int>('getRecordStartSampleTime');
  }

  static Future<String> mixWithOffset({
    required String referencePath,
    required String vocalPath,
    required String outPath,
    required int vocalOffsetSamples,
    double refGain = 1.0,
    double vocalGain = 1.0,
  }) async {
    final result = await _m.invokeMethod<String>('mixWithOffset', {
      'referencePath': referencePath,
      'vocalPath': vocalPath,
      'outPath': outPath,
      'vocalOffsetSamples': vocalOffsetSamples,
      'refGain': refGain,
      'vocalGain': vocalGain,
    });
    return result ?? '';
  }
}
