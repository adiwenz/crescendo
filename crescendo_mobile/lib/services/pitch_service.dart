import 'dart:async';

import '../models/pitch_frame.dart' as recording;
import 'recording_service.dart';

class PitchFrame {
  final double frequencyHz;
  final double confidence;
  final DateTime ts;

  const PitchFrame({
    required this.frequencyHz,
    required this.confidence,
    required this.ts,
  });
}

class PitchService {
  final RecordingService _recording;
  final StreamController<PitchFrame> _controller =
      StreamController<PitchFrame>.broadcast();
  StreamSubscription<recording.PitchFrame>? _sub;
  bool _running = false;

  PitchService({RecordingService? recording})
      : _recording = recording ?? RecordingService();

  Stream<PitchFrame> get stream => _controller.stream;

  Future<void> start() async {
    if (_running) return;
    await _recording.start();
    _running = true;
    _sub = _recording.liveStream.listen((frame) {
      final hz = frame.hz;
      final hasPitch = hz != null && hz > 0 && hz.isFinite;
      // TODO: Replace with real confidence from detector when available.
      final confidence = hasPitch ? 1.0 : 0.0;
      _controller.add(PitchFrame(
        frequencyHz: hasPitch ? hz! : 0,
        confidence: confidence,
        ts: DateTime.now(),
      ));
    });
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _sub?.cancel();
    _sub = null;
    await _recording.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
