import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_pitch_detection/flutter_pitch_detection.dart';
import 'package:crescendo_mobile/core/interfaces/i_pitch_detector.dart';

class RealPitchDetector implements IPitchDetector {
  final FlutterPitchDetection _detector = FlutterPitchDetection();
  final _controller = StreamController<PitchResult>.broadcast();
  StreamSubscription? _sub;

  @override
  Stream<PitchResult> get pitchStream => _controller.stream;

  @override
  Future<void> processPCM(Uint8List buffer) async {
    // real plugin doesn't support manual PCM feeding usually, or it's native.
    // wrapper ignores this or throws.
  }

  @override
  Future<void> start(Function(PitchResult p1) onPitchDetected) async {
    // We map internal stream to callback to match interface legacy style OR stream style
    // Interface has start(callback) AND stream.
    
    // Wire up stream listening
    _sub = _detector.onPitchDetected.listen((event) {
      final freq = (event['frequency'] as num?)?.toDouble() ?? 0.0;
      final prob = (event['accuracy'] as num?)?.toDouble() ?? 0.0;
      final result = PitchResult(frequency: freq, isVoiced: freq > 0, probability: prob);
      
      _controller.add(result);
      onPitchDetected(result);
    });
    
    await _detector.startDetection(sampleRate: 44100, bufferSize: 8192);
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _detector.stopDetection();
  }
}
