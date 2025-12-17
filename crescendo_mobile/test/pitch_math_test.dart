import 'package:flutter_test/flutter_test.dart';

import 'package:crescendo_mobile/utils/pitch_math.dart';

void main() {
  test('PitchMath mapping is deterministic', () {
    final midi = PitchMath.hzToMidi(440.0);
    expect(midi, closeTo(69.0, 0.001));
    final y = PitchMath.midiToY(
      midi: midi,
      height: 100,
      midiMin: 60,
      midiMax: 72,
    );
    final expected = 100 - ((69 - 60) / (72 - 60)) * 100;
    expect(y, closeTo(expected, 0.001));
  });
}
