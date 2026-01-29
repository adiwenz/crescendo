import 'package:flutter/foundation.dart';

/// Configuration for playback to ensure consistent audio across exercise and review modes
class MidiPlaybackConfig {
  /// Volume (0.0 to 1.0)
  final double volume;
  
  /// Enable pitch bend
  final bool enablePitchBend;
  
  /// Initial pitch bend value (0-16383, 8192 = center/no bend)
  final int initialPitchBend;
  
  /// Transpose semitones (should be 0 if notes are already final)
  final int transposeSemitones;
  
  /// Debug tag for logging ('exercise' or 'review')
  final String debugTag;

  const MidiPlaybackConfig({
    this.volume = 1.0,
    this.enablePitchBend = false,
    this.initialPitchBend = 8192, // Center (no bend)
    this.transposeSemitones = 0,
    required this.debugTag,
  });

  /// Default config for exercise playback
  factory MidiPlaybackConfig.exercise() {
    return const MidiPlaybackConfig(
      debugTag: 'exercise',
    );
  }

  /// Default config for review playback (identical to exercise)
  factory MidiPlaybackConfig.review() {
    return const MidiPlaybackConfig(
      debugTag: 'review',
    );
  }

  /// Check if this config matches another config (for validation)
  bool matches(MidiPlaybackConfig other) {
    return (volume - other.volume).abs() < 0.01 &&
        enablePitchBend == other.enablePitchBend &&
        initialPitchBend == other.initialPitchBend &&
        transposeSemitones == other.transposeSemitones;
  }

  /// Get differences between this config and another
  List<String> getDifferences(MidiPlaybackConfig other) {
    final differences = <String>[];
    if ((volume - other.volume).abs() >= 0.01) {
      differences.add('volume: $volume vs ${other.volume}');
    }
    if (enablePitchBend != other.enablePitchBend) {
      differences.add('enablePitchBend: $enablePitchBend vs ${other.enablePitchBend}');
    }
    if (initialPitchBend != other.initialPitchBend) {
      differences.add('initialPitchBend: $initialPitchBend vs ${other.initialPitchBend}');
    }
    if (transposeSemitones != other.transposeSemitones) {
      differences.add('transposeSemitones: $transposeSemitones vs ${other.transposeSemitones}');
    }
    return differences;
  }

  @override
  String toString() {
    return 'MidiPlaybackConfig('
        'volume=$volume, '
        'pitchBend=${enablePitchBend ? initialPitchBend : "disabled"}, '
        'transpose=$transposeSemitones, tag=$debugTag)';
  }
}
