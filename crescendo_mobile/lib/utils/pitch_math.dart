import 'dart:math' as math;

class PitchMath {
  static double hzToMidi(double hz) {
    if (hz <= 0) return 0;
    return 69 + 12 * (math.log(hz / 440.0) / math.ln2);
  }

  static double midiToY({
    required double midi,
    required double height,
    required int midiMin,
    required int midiMax,
  }) {
    final clamped = midi.clamp(midiMin.toDouble(), midiMax.toDouble());
    final ratio = (clamped - midiMin) / (midiMax - midiMin);
    return height - ratio * height;
  }

  static String midiToName(int midi) {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (midi / 12).floor() - 1;
    return '${names[midi % 12]}$octave';
  }
}
