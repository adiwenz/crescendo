import 'dart:math' as math;

import 'package:crescendo_mobile/audio/hold_stability.dart';
import 'package:crescendo_mobile/models/pitch_frame.dart';
import 'package:test/test.dart';

void main() {
  group('computeHoldMetrics', () {
    test('perfect hold hits max duration with near-zero stddev', () {
      final frames = List<PitchFrame>.generate(
        11,
        (i) => PitchFrame(time: i * 0.1, hz: 440),
      );

      final m = computeHoldMetrics(
        frames: frames,
        noteStart: 0,
        noteEnd: 1.0,
        targetHz: 440,
      );

      expect(m.maxContinuousOnPitchSec, closeTo(1.0, 0.11));
      expect(m.holdPercent, closeTo(1.0, 0.05));
      expect(m.stabilityCentsStdDev, isNotNull);
      expect(m.stabilityCentsStdDev!.abs(), lessThan(0.1));
    });

    test('vibrato within threshold counts as hold with non-zero stddev', () {
      final frames = <PitchFrame>[];
      for (var i = 0; i < 20; i++) {
        final t = i * 0.05;
        final cents = 10 * math.sin(t * math.pi * 2);
        final hz = 440 * math.pow(2, cents / 1200);
        frames.add(PitchFrame(time: t, hz: hz));
      }

      final m = computeHoldMetrics(
        frames: frames,
        noteStart: 0,
        noteEnd: 1.0,
        targetHz: 440,
      );

      expect(m.maxContinuousOnPitchSec, greaterThan(0.9));
      expect(m.stabilityCentsStdDev, isNotNull);
      expect(m.stabilityCentsStdDev, greaterThan(0.1));
    });

    test('drift outside threshold truncates hold', () {
      final frames = <PitchFrame>[
        PitchFrame(time: 0.0, hz: 440),
        PitchFrame(time: 0.1, hz: 440 * math.pow(2, 20 / 1200)),
        PitchFrame(time: 0.2, hz: 440 * math.pow(2, 26 / 1200)), // outside
        PitchFrame(time: 0.3, hz: 440 * math.pow(2, 30 / 1200)),
      ];

      final m = computeHoldMetrics(
        frames: frames,
        noteStart: 0,
        noteEnd: 0.4,
        targetHz: 440,
      );

      expect(m.maxContinuousOnPitchSec, closeTo(0.1, 0.05));
      expect(m.holdPercent, closeTo(0.25, 0.1));
    });

    test('unvoiced gaps break hold', () {
      final frames = <PitchFrame>[
        PitchFrame(time: 0.0, hz: 440),
        PitchFrame(time: 0.1, hz: 440),
        PitchFrame(time: 0.2, hz: null), // unvoiced
        PitchFrame(time: 0.3, hz: 440),
        PitchFrame(time: 0.4, hz: 440),
      ];

      final m = computeHoldMetrics(
        frames: frames,
        noteStart: 0,
        noteEnd: 0.5,
        targetHz: 440,
      );

      expect(m.maxContinuousOnPitchSec, closeTo(0.2, 0.05));
    });

    test('irregular gaps break hold when spacing is too large', () {
      final frames = <PitchFrame>[
        PitchFrame(time: 0.0, hz: 440),
        PitchFrame(time: 0.1, hz: 440),
        PitchFrame(time: 0.5, hz: 440), // big gap -> new run
        PitchFrame(time: 0.6, hz: 440),
      ];

      final m = computeHoldMetrics(
        frames: frames,
        noteStart: 0,
        noteEnd: 0.7,
        targetHz: 440,
      );

      // Best continuous run should be ~0.1 sec (two tight frames).
      expect(m.maxContinuousOnPitchSec, closeTo(0.1, 0.05));
    });
  });
}
