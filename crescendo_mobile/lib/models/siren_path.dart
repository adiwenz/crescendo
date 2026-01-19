/// Control point for Sirens visual path rendering
class SirenPoint {
  final double tSec; // Time in seconds (relative to timeline start, includes lead-in)
  final double midiFloat; // MIDI value as float for smooth interpolation

  const SirenPoint({
    required this.tSec,
    required this.midiFloat,
  });
}

/// Visual path for Sirens exercise (continuous curve)
class SirenPath {
  final List<SirenPoint> points;

  const SirenPath({required this.points});

  bool get isEmpty => points.isEmpty;
  int get length => points.length;
}
