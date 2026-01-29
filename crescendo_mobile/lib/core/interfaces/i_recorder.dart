import 'dart:async';

abstract class IRecorder {
  Future<bool> hasPermission();
  Future<void> start(String path, {int? sampleRate, int? bitRate});
  Future<String?> stop();
  Future<bool> isRecording();
  Future<void> dispose();
  Stream<double> get amplitudeStream; // For visualizations if needed
}
