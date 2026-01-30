import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_mobile/utils/daily_completion_utils.dart';

void main() {
  setUpAll(() {
    DailyCompletionUtils.initialize();
  });

  group('DailyCompletionUtils.generateDateKey', () {
    test('returns YYYY-MM-DD format', () {
      // Jan 15, 2025 noon UTC → in NY same date (winter: UTC-5)
      final utc = DateTime.utc(2025, 1, 15, 12, 0, 0);
      final key = DailyCompletionUtils.generateDateKey(utc);
      expect(key, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(key, '2025-01-15');
    });

    test('uses America/New_York so UTC midnight can be previous calendar day in NY', () {
      // Jan 15 05:00 UTC = Jan 15 00:00 Eastern (midnight)
      final utc = DateTime.utc(2025, 1, 15, 5, 0, 0);
      final key = DailyCompletionUtils.generateDateKey(utc);
      expect(key, '2025-01-15');
      // Jan 15 04:59 UTC = Jan 14 23:59 Eastern
      final utcPrev = DateTime.utc(2025, 1, 15, 4, 59, 0);
      final keyPrev = DailyCompletionUtils.generateDateKey(utcPrev);
      expect(keyPrev, '2025-01-14');
    });

    test('pads month and day with zero', () {
      final utc = DateTime.utc(2025, 3, 7, 14, 0, 0);
      final key = DailyCompletionUtils.generateDateKey(utc);
      expect(key, '2025-03-07');
    });
  });

  group('DailyCompletionUtils.countsForDailyEffortCountdown', () {
    test('returns false when session did not end normally (user quit)', () {
      expect(
        DailyCompletionUtils.countsForDailyEffortCountdown(
          sessionEndedNormally: false,
          completionPercent: 1.0,
          elapsedSec: 30,
          requiredSec: 30,
        ),
        false,
      );
      expect(
        DailyCompletionUtils.countsForDailyEffortCountdown(
          sessionEndedNormally: false,
          completionPercent: 0.5,
          elapsedSec: 15,
          requiredSec: 30,
        ),
        false,
      );
    });

    test('returns true when session ended normally and completionPercent >= 1.0', () {
      expect(
        DailyCompletionUtils.countsForDailyEffortCountdown(
          sessionEndedNormally: true,
          completionPercent: 1.0,
          elapsedSec: 30,
          requiredSec: 30,
        ),
        true,
      );
    });

    test('returns true when session ended normally and elapsedSec >= requiredSec - tolerance', () {
      // requiredSec 30, tolerance 2 → need elapsedSec >= 28
      expect(
        DailyCompletionUtils.countsForDailyEffortCountdown(
          sessionEndedNormally: true,
          completionPercent: null,
          elapsedSec: 28,
          requiredSec: 30,
        ),
        true,
      );
      expect(
        DailyCompletionUtils.countsForDailyEffortCountdown(
          sessionEndedNormally: true,
          completionPercent: null,
          elapsedSec: 30,
          requiredSec: 30,
        ),
        true,
      );
    });

    test('returns false when session ended normally but quit early (below tolerance)', () {
      expect(
        DailyCompletionUtils.countsForDailyEffortCountdown(
          sessionEndedNormally: true,
          completionPercent: 0.5,
          elapsedSec: 15,
          requiredSec: 30,
        ),
        false,
      );
      expect(
        DailyCompletionUtils.countsForDailyEffortCountdown(
          sessionEndedNormally: true,
          completionPercent: null,
          elapsedSec: 25,
          requiredSec: 30,
        ),
        false,
      );
    });

    test('returns true when session ended normally and completionPercent >= 0.95 (fallback)', () {
      expect(
        DailyCompletionUtils.countsForDailyEffortCountdown(
          sessionEndedNormally: true,
          completionPercent: 0.96,
          elapsedSec: null,
          requiredSec: null,
        ),
        true,
      );
    });
  });

  group('DailyCompletionUtils.countsForDailyEffortPitchHighway', () {
    test('returns false for null completionPercent', () {
      expect(DailyCompletionUtils.countsForDailyEffortPitchHighway(null), false);
    });

    test('returns false below 95%', () {
      expect(DailyCompletionUtils.countsForDailyEffortPitchHighway(0.0), false);
      expect(DailyCompletionUtils.countsForDailyEffortPitchHighway(0.5), false);
      expect(DailyCompletionUtils.countsForDailyEffortPitchHighway(0.94), false);
    });

    test('returns true at or above 95%', () {
      expect(DailyCompletionUtils.countsForDailyEffortPitchHighway(0.95), true);
      expect(DailyCompletionUtils.countsForDailyEffortPitchHighway(0.99), true);
      expect(DailyCompletionUtils.countsForDailyEffortPitchHighway(1.0), true);
    });
  });

  group('DailyCompletionUtils.countsForDailyEffort (generic)', () {
    test('returns false for null', () {
      expect(DailyCompletionUtils.countsForDailyEffort(null), false);
    });

    test('returns false below 95%', () {
      expect(DailyCompletionUtils.countsForDailyEffort(0.94), false);
    });

    test('returns true at or above 95%', () {
      expect(DailyCompletionUtils.countsForDailyEffort(0.95), true);
      expect(DailyCompletionUtils.countsForDailyEffort(1.0), true);
    });
  });

  group('Edge cases (spec)', () {
    test('Countdown: start + quit early → NOT counted', () {
      expect(
        DailyCompletionUtils.countsForDailyEffortCountdown(
          sessionEndedNormally: false,
          completionPercent: 0.3,
          elapsedSec: 10,
          requiredSec: 30,
        ),
        false,
      );
    });

    test('Countdown: start + reach end → counted', () {
      expect(
        DailyCompletionUtils.countsForDailyEffortCountdown(
          sessionEndedNormally: true,
          completionPercent: 1.0,
          elapsedSec: 30,
          requiredSec: 30,
        ),
        true,
      );
    });

    test('PitchHighway: partial completion → NOT counted', () {
      expect(DailyCompletionUtils.countsForDailyEffortPitchHighway(0.8), false);
    });

    test('PitchHighway: completed (95%+) → counted', () {
      expect(DailyCompletionUtils.countsForDailyEffortPitchHighway(0.95), true);
    });
  });
}
