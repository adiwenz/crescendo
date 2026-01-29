import 'dart:async';
import 'package:crescendo_mobile/core/interfaces/i_recorder.dart';

class FakeRecorder implements IRecorder {
  bool _isRecording = false;
  final _ampController = StreamController<double>.broadcast();

  // Test helper
  void emitAmplitude(double val) {
    _ampController.add(val);
  }

  @override
  Stream<double> get amplitudeStream => _ampController.stream;

  @override
  Future<void> dispose() async {
    await _ampController.close();
  }

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> isRecording() async => _isRecording;

  @override
  Future<void> start(String path, {int? sampleRate, int? bitRate}) async {
    _isRecording = true;
  }

  @override
  Future<String?> stop() async {
    _isRecording = false;
    return '/fake/recording.wav';
  }
}
