import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_pitch_detection/flutter_pitch_detection.dart';
import '../utils/audio_constants.dart';

class PitchData {
  final double frequency;
  final String note;
  final double cents;
  final double probability;

  PitchData({
    required this.frequency,
    required this.note,
    required this.cents,
    required this.probability,
  });
}

class PitchDetectionService {
  final FlutterPitchDetection _detector = FlutterPitchDetection();
  final _controller = StreamController<PitchData>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _running = false;

  Stream<PitchData> get pitchStream => _controller.stream;

  Future<void> start({int sampleRate = AudioConstants.audioSampleRate, int bufferSize = 8192}) async {
    if (_running) return;
    _running = true;
    await _detector.startDetection(sampleRate: sampleRate, bufferSize: bufferSize);
    _sub = _detector.onPitchDetected.listen((event) {
      final freq = (event['frequency'] as num?)?.toDouble() ?? 0.0;
      if (freq <= 0 || !freq.isFinite) return;
      final midi = 69 + 12 * math.log(freq / 440.0) / math.ln2;
      final rounded = midi.round();
      final cents = (midi - rounded) * 100;
      final name = _noteName(rounded);
      final prob = (event['accuracy'] as num?)?.toDouble() ?? 0.0;
      _controller.add(PitchData(
        frequency: freq,
        note: name,
        cents: cents,
        probability: prob,
      ));
    });
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _sub?.cancel();
    _sub = null;
    await _detector.stopDetection();
  }

  String _noteName(int midi) {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final name = names[midi % 12];
    final octave = (midi ~/ 12) - 1;
    return '$name$octave';
  }
}
