import '../models/pitch_highway_difficulty.dart';
import '../models/pitch_segment.dart';

class PitchHighwayTempo {
  static const double easyMultiplier = 0.80;
  static const double mediumMultiplier = 1.00;
  static const double hardMultiplier = 1.15;
  static const double hardReducedMultiplier = 1.10;
  static const double maxMultiplier = 1.20;
  static const int minDurationMs = 200;
  static const double shortNoteMedianSec = 0.35;

  static double multiplierFor(
    PitchHighwayDifficulty difficulty,
    List<PitchSegment> segments,
  ) {
    var base = switch (difficulty) {
      PitchHighwayDifficulty.easy => easyMultiplier,
      PitchHighwayDifficulty.medium => mediumMultiplier,
      PitchHighwayDifficulty.hard => hardMultiplier,
    };
    if (difficulty == PitchHighwayDifficulty.hard &&
        _medianDurationSec(segments) < shortNoteMedianSec) {
      base = hardReducedMultiplier;
    }
    return base.clamp(0.01, maxMultiplier);
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

  static double _medianDurationSec(List<PitchSegment> segments) {
    if (segments.isEmpty) return 0.0;
    final durations = segments
        .map((s) => (s.endMs - s.startMs) / 1000.0)
        .where((d) => d.isFinite && d > 0)
        .toList();
    if (durations.isEmpty) return 0.0;
    durations.sort();
    final mid = durations.length ~/ 2;
    if (durations.length.isOdd) return durations[mid];
    return (durations[mid - 1] + durations[mid]) / 2;
  }
}
