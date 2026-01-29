import 'package:flutter_test/flutter_test.dart';

import 'package:crescendo_mobile/models/pitch_frame.dart';
import 'package:crescendo_mobile/services/scoring_service.dart';

void main() {
  test('scoring computes mean and percentages', () {
    final frames = [
      PitchFrame(time: 0, centsError: 10, hz: 0, midi: 60),
      PitchFrame(time: 0.1, centsError: 30, hz: 0, midi: 60),
      PitchFrame(time: 0.2, centsError: 60, hz: 0, midi: 60),
    ];
    final metrics = ScoringService().score(frames);
    expect(metrics.meanAbsCents, closeTo(33.3, 0.2));
    expect(metrics.pctWithin20, closeTo(33.3, 0.1));
    expect(metrics.pctWithin50, closeTo(66.6, 0.1));
    expect(metrics.validFrames, 3);
  });
}
