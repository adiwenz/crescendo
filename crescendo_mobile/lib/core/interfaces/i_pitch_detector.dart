import 'dart:async';
import 'dart:typed_data';

class PitchResult {
  final double frequency;
  final bool isVoiced;
  final double probability;
  
  PitchResult({required this.frequency, required this.isVoiced, required this.probability});
}

abstract class IPitchDetector {
  Future<void> start(Function(PitchResult) onPitchDetected);
  Future<void> stop();
  Future<void> processPCM(Uint8List buffer); // For manual processing/testing
  Stream<PitchResult> get pitchStream;
}
