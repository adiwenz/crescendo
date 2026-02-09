
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

/// A specific chord event scheduled by tick.
class TickChordEvent {
  final int startTick;
  final int durationTicks;
  final Chord chord;
  final int octaveOffset; // e.g. -1 for bass, 0 for mid

  const TickChordEvent({
    required this.startTick,
    required this.durationTicks,
    required this.chord,
    this.octaveOffset = 0,
  });

  int get endTick => startTick + durationTicks;
}

/// A specific key change/modulation scheduled by tick.
class TickModulationEvent {
  final int tick;
  final int semitoneDelta; // Relative change (+1 semitone)
  
  const TickModulationEvent({
    required this.tick,
    required this.semitoneDelta,
  });
}

/// Helper for musical time conversions (Tick <-> Seconds/Samples).
class MusicalClock {
  final int bpm;
  final int timeSignatureTop; // Beats per bar
  final int sampleRate;
  
  static const int ppq = 480; // Pulses Per Quarter note (Standard resolution)

  const MusicalClock({
    required this.bpm,
    required this.timeSignatureTop,
    required this.sampleRate,
  });

  /// Calculates the number of samples per tick.
  double get samplesPerTick {
    // Minutes per tick = 1 / (BPM * PPQ)
    // Seconds per tick = 60 / (BPM * PPQ)
    // Samples per tick = (60 * SampleRate) / (BPM * PPQ)
    return (60.0 * sampleRate) / (bpm * ppq);
  }

  /// Calculates the tick for a specific bar/beat location.
  /// [bar] 1-based bar index (starts at 1)
  /// [beat] 1-based beat index (starts at 1)
  int tickFor({required int bar, required int beat, int subdivision = 0}) {
    // (bar-1) * (beatsPerBar * PPQ) + (beat-1) * PPQ + subdivision
    // Assuming 4/4 or X/4 time where beat is a quarter note
    final barTicks = (bar - 1) * timeSignatureTop * ppq;
    final beatTicks = (beat - 1) * ppq;
    return barTicks + beatTicks + subdivision;
  }
  
  /// Converts ticks to seconds.
  double ticksToSeconds(int ticks) {
    // Seconds per tick = 60 / (BPM * PPQ)
    return ticks * (60.0 / (bpm * ppq));
  }
  
  /// Converts seconds to ticks.
  int secondsToTicks(double seconds) {
    return (seconds * (bpm * ppq) / 60.0).round();
  }
}
