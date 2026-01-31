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
}
