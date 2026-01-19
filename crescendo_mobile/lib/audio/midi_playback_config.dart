import 'package:flutter/foundation.dart';

/// Configuration for MIDI playback to ensure consistent audio across exercise and review modes
class MidiPlaybackConfig {
  /// SoundFont asset path (e.g., 'assets/soundfonts/default.sf2')
  final String soundFontAssetPath;
  
  /// SoundFont name/bundle identifier
  final String soundFontName;
  
  /// MIDI program (preset) number (0-127)
  final int program;
  
  /// MIDI bank MSB (Most Significant Byte) (0-127)
  final int bankMSB;
  
  /// MIDI bank LSB (Least Significant Byte) (0-127)
  final int bankLSB;
  
  /// MIDI channel (0-15, typically 0-15 for 16 channels)
  final int channel;
  
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
    this.soundFontAssetPath = 'assets/soundfonts/default.sf2',
    this.soundFontName = 'default.sf2',
    this.program = 0, // Default piano program
    this.bankMSB = 0,
    this.bankLSB = 0,
    this.channel = 0,
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
    return soundFontAssetPath == other.soundFontAssetPath &&
        soundFontName == other.soundFontName &&
        program == other.program &&
        bankMSB == other.bankMSB &&
        bankLSB == other.bankLSB &&
        channel == other.channel &&
        (volume - other.volume).abs() < 0.01 &&
        enablePitchBend == other.enablePitchBend &&
        initialPitchBend == other.initialPitchBend &&
        transposeSemitones == other.transposeSemitones;
  }

  /// Get differences between this config and another
  List<String> getDifferences(MidiPlaybackConfig other) {
    final differences = <String>[];
    if (soundFontAssetPath != other.soundFontAssetPath) {
      differences.add('soundFontAssetPath: $soundFontAssetPath vs ${other.soundFontAssetPath}');
    }
    if (soundFontName != other.soundFontName) {
      differences.add('soundFontName: $soundFontName vs ${other.soundFontName}');
    }
    if (program != other.program) {
      differences.add('program: $program vs ${other.program}');
    }
    if (bankMSB != other.bankMSB) {
      differences.add('bankMSB: $bankMSB vs ${other.bankMSB}');
    }
    if (bankLSB != other.bankLSB) {
      differences.add('bankLSB: $bankLSB vs ${other.bankLSB}');
    }
    if (channel != other.channel) {
      differences.add('channel: $channel vs ${other.channel}');
    }
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
        'soundFont=$soundFontName, '
        'program=$program, bankMSB=$bankMSB bankLSB=$bankLSB, '
        'channel=$channel, volume=$volume, '
        'pitchBend=${enablePitchBend ? initialPitchBend : "disabled"}, '
        'transpose=$transposeSemitones, tag=$debugTag)';
  }
}
