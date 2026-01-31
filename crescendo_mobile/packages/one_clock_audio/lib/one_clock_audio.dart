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

  static Future<void> start(OneClockStartConfig config) async {
    await _m.invokeMethod('start', config.toMap());
  }

  static Future<void> stop() => _m.invokeMethod('stop');

  static Future<void> setPlaybackGain(double gain) =>
      _m.invokeMethod('setGain', {'gain': gain});
}
