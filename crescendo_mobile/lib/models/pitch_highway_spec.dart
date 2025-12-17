import 'pitch_segment.dart';

class PitchHighwaySpec {
  final List<PitchSegment> segments;

  const PitchHighwaySpec({required this.segments});

  int get totalMs {
    if (segments.isEmpty) return 0;
    return segments.map((s) => s.endMs).reduce((a, b) => a > b ? a : b);
  }
}
