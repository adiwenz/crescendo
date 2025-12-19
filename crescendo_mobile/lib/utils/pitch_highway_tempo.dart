import '../models/pitch_highway_difficulty.dart';
import '../models/pitch_segment.dart';

class PitchHighwayTempo {
  static const double level1Multiplier = 0.85;
  static const double level2Multiplier = 1.00;
  static const double level3Multiplier = 1.15;
  static const double maxMultiplier = 1.20;
  static const double basePixelsPerSecond = 160;
  static const int minDurationMs = 200;

  static double multiplierFor(
    PitchHighwayDifficulty difficulty,
    List<PitchSegment> _segments,
  ) {
    final base = switch (difficulty) {
      PitchHighwayDifficulty.easy => level1Multiplier,
      PitchHighwayDifficulty.medium => level2Multiplier,
      PitchHighwayDifficulty.hard => level3Multiplier,
    };
    return base.clamp(0.01, maxMultiplier);
  }

  static double pixelsPerSecondFor(PitchHighwayDifficulty difficulty) {
    return basePixelsPerSecond * multiplierFor(difficulty, const []);
  }

  static List<PitchSegment> scaleSegments(
    List<PitchSegment> segments,
    double multiplier,
  ) {
    return segments
        .map((seg) {
          final durationMs = seg.endMs - seg.startMs;
          final scaledStartMs = (seg.startMs / multiplier).round();
          final scaledDurationMs =
              (durationMs / multiplier).round().clamp(minDurationMs, 1 << 30);
          return PitchSegment(
            startMs: scaledStartMs,
            endMs: scaledStartMs + scaledDurationMs,
            midiNote: seg.midiNote,
            toleranceCents: seg.toleranceCents,
            label: seg.label,
            startMidi: seg.startMidi,
            endMidi: seg.endMidi,
          );
        })
        .toList(growable: false);
  }

}
