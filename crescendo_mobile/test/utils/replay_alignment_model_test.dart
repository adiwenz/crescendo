import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_mobile/utils/replay_alignment_model.dart';

void main() {
  group('ReplayAlignmentModel', () {
    test('micTimeToExerciseTime handles positive offset (Mic Late)', () {
      // Mic is LATE by 0.5s.
      // Event A happens at 1.0s in Ref.
      // Event A happens at 1.5s in Mic.
      // We want micTime(1.5) -> 1.0.
      final model = ReplayAlignmentModel(micOffsetSec: 0.5, leadInSec: 2.0);
      
      expect(model.micTimeToExerciseTime(1.5), closeTo(1.0, 0.001));
      expect(model.micTimeToExerciseTime(0.5), closeTo(0.0, 0.001)); // Start of exercise
    });

    test('micTimeToExerciseTime handles negative offset (Mic Early)', () {
      // Mic is EARLY by 0.5s.
      // Event A happens at 1.0s in Ref.
      // Event A happens at 0.5s in Mic.
      // We want micTime(0.5) -> 1.0.
      // t_ref = t_mic - (-0.5) = t_mic + 0.5
      final model = ReplayAlignmentModel(micOffsetSec: -0.5, leadInSec: 2.0);
      
      expect(model.micTimeToExerciseTime(0.5), closeTo(1.0, 0.001));
    });

    test('refPositionToExerciseTime is 1:1', () {
      final model = ReplayAlignmentModel(micOffsetSec: 0.5);
      expect(model.refPositionToExerciseTime(2.0), 2.0);
    });
  });
}
