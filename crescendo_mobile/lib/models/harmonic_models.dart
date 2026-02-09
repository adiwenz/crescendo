
enum ChordQuality {
  major,
  minor,
  diminished,
  augmented,
  dominant7,
  major7,
  minor7,
  sus4,
  sus2,
}

/// Represents a scale degree (1-7) to allow key-agnostic chord definitions.
class ScaleDegree {
  final int degree; // 1 = tonic, 5 = dominant, etc.
  final int accidental; // -1 = flat, 0 = natural, 1 = sharp

  const ScaleDegree(this.degree, {this.accidental = 0})
      : assert(degree >= 1 && degree <= 7);

  static const I = ScaleDegree(1);
  static const ii = ScaleDegree(2); // Major scale supertonic is minor
  static const iii = ScaleDegree(3);
  static const IV = ScaleDegree(4);
  static const V = ScaleDegree(5);
  static const vi = ScaleDegree(6);
  static const viiDim = ScaleDegree(7); // Major scale leading tone is dim

  @override
  String toString() {
    final acc = accidental == 0
        ? ''
        : accidental > 0
            ? '#' * accidental
            : 'b' * (-accidental);
    return '$acc$degree';
  }
}

/// Represents a chord built on a scale degree.
class Chord {
  final ScaleDegree root;
  final ChordQuality quality;
  final List<int> extensions; // e.g., 9, 11, 13

  const Chord({
    required this.root,
    this.quality = ChordQuality.major,
    this.extensions = const [],
  });
  
  // Common chords
  static const I_Major = Chord(root: ScaleDegree.I, quality: ChordQuality.major);
  static const V_Major = Chord(root: ScaleDegree.V, quality: ChordQuality.major);
  static const vi_Minor = Chord(root: ScaleDegree.vi, quality: ChordQuality.minor);
  static const IV_Major = Chord(root: ScaleDegree.IV, quality: ChordQuality.major);

  @override
  String toString() => '${root.toString()}.${quality.name}';
}

/// A chord event positioned in time relative to the pattern start.
class ChordEvent {
  final Chord chord;
  final double startMs;
  final double durationMs;

  const ChordEvent({
    required this.chord,
    required this.startMs,
    required this.durationMs,
  });
  
  double get endMs => startMs + durationMs;
  
  ChordEvent copyWith({
    Chord? chord,
    double? startMs,
    double? durationMs,
  }) {
    return ChordEvent(
      chord: chord ?? this.chord,
      startMs: startMs ?? this.startMs,
      durationMs: durationMs ?? this.durationMs,
    );
  }
}
