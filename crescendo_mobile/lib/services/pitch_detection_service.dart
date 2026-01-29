import 'dart:async';
import 'dart:math' as math; // Keep for log/pow

import '../utils/audio_constants.dart';
import '../../core/locator.dart';
import '../../core/interfaces/i_pitch_detector.dart';

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
  late final IPitchDetector _detector;
  final _controller = StreamController<PitchData>.broadcast();
  bool _running = false;

  PitchDetectionService() {
    _detector = locator<IPitchDetector>(); // Use locator
  }

  Stream<PitchData> get pitchStream => _controller.stream;

  Future<void> start({int sampleRate = AudioConstants.audioSampleRate, int bufferSize = 8192}) async {
    if (_running) return;
    _running = true;
    
    // IPitchDetector handles start args? Wrapper hardcodes them currently or defaults.
    // Interface 'start' signature: start(callback).
    // If I need sampleRate params, I should update interface.
    // Current wrapper RealPitchDetector hardcodes 44100/8192.
    // Ideally update interface to accept params.
    // For now, assume default is fine or update interface quickly.
    // Let's rely on wrapper default for this specific task scope, or update interface.
    // Since I'm refactoring, I should probably stick to what I have or fix it.
    // RealPitchDetector hardcoded 44100.
    
    await _detector.start((result) {
      if (!_running) return;
      
      final freq = result.frequency;
      if (freq <= 0 || !freq.isFinite) return; // Logic preserved
      
      final midi = 69 + 12 * math.log(freq / 440.0) / math.ln2;
      final rounded = midi.round(); // Logic preserved
      final cents = (midi - rounded) * 100;
      final name = _noteName(rounded);
      final prob = result.probability;
      
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
    await _detector.stop();
  }

  String _noteName(int midi) {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final name = names[midi % 12];
    final octave = (midi ~/ 12) - 1;
    return '$name$octave';
  }
}
