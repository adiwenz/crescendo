class TailPoint {
  final double tSec;
  final double yPx;
  final bool voiced;

  const TailPoint({
    required this.tSec,
    required this.yPx,
    required this.voiced,
  });
}

class PitchTailBuffer {
  final List<TailPoint> points = [];

  void addPoint({
    required double tSec,
    required double yPx,
    required bool voiced,
  }) {
    points.add(TailPoint(tSec: tSec, yPx: yPx, voiced: voiced));
  }

  void pruneOlderThan(double cutoffSec) {
    while (points.isNotEmpty && points.first.tSec < cutoffSec) {
      points.removeAt(0);
    }
  }

  void clear() {
    points.clear();
  }
}
