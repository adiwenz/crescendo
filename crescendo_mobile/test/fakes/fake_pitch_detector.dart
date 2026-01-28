import 'dart:async';
import 'dart:typed_data';
import 'package:crescendo_mobile/core/interfaces/i_pitch_detector.dart';

class FakePitchDetector implements IPitchDetector {
  final _controller = StreamController<PitchResult>.broadcast();
  Function(PitchResult)? _currentCallback;

  // Test helper
  void emitPitch(double frequency, {bool isVoiced = true, double probability = 1.0}) {
    final result = PitchResult(frequency: frequency, isVoiced: isVoiced, probability: probability);
    _controller.add(result);
    if (_currentCallback != null) {
      _currentCallback!(result);
    }
  }

  @override
  Stream<PitchResult> get pitchStream => _controller.stream;

  @override
  Future<void> processPCM(Uint8List buffer) async {
    // No-op for manual processing in fake
  }

  @override
  Future<void> start(Function(PitchResult p1) onPitchDetected) async {
    _currentCallback = onPitchDetected;
  }

  @override
  Future<void> stop() async {
    _currentCallback = null;
  }
}
