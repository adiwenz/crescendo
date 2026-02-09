import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Immutable specification for a generated reference WAV file.
/// Used to create stable cache keys and ensure audio params are consistent.
class RefSpec {
  final String exerciseId;
  final int lowMidi;
  final int highMidi;
  final int transpositionSemitones;
  final int tempoBpm;
  final double sampleRate;
  final int channels;
  final int bitDepth;
  final String synthPreset;
  final String renderVersion;

  // Additional options that might affect generation
  final Map<String, dynamic> extraOptions;

  const RefSpec({
    required this.exerciseId,
    required this.lowMidi,
    required this.highMidi,
    this.transpositionSemitones = 0,
    this.tempoBpm = 120, // Default, often not used for free-time exercises but good to have
    this.sampleRate = 48000.0,
    this.channels = 1,
    this.bitDepth = 16,
    this.synthPreset = 'default_piano',
    // Increment this whenever the generation logic (math) changes to invalidate old caches
    this.renderVersion = 'v1', 
    this.extraOptions = const {},
  });

  /// Generates a canonical JSON representation with sorted keys for stable hashing.
  Map<String, dynamic> toCanonicalJson() {
    // Sort extra options keys
    final sortedExtra = Map.fromEntries(
      extraOptions.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );

    return {
      'bitDepth': bitDepth,
      'channels': channels,
      'exerciseId': exerciseId,
      'extraOptions': sortedExtra,
      'highMidi': highMidi,
      'lowMidi': lowMidi,
      'renderVersion': renderVersion,
      'sampleRate': sampleRate,
      'synthPreset': synthPreset,
      'tempoBpm': tempoBpm,
      'transpositionSemitones': transpositionSemitones,
    };
  }

  /// Computes a deterministic SHA-256 hash of the canonical JSON.
  String get cacheKey {
    final jsonString = jsonEncode(toCanonicalJson());
    final bytes = utf8.encode(jsonString);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16); // 16 chars is usually enough collision resistance for local cache
  }

  /// Returns a human-readable filename with the hash appended.
  /// Format: {exerciseId}_{low}-{high}_v{ver}_{hash}.wav
  String get filename {
    final safeId = exerciseId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return '${safeId}_${lowMidi}-${highMidi}_${renderVersion}_$cacheKey.wav';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RefSpec &&
          runtimeType == other.runtimeType &&
          cacheKey == other.cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;

  @override
  String toString() => 'RefSpec($filename)';
}
