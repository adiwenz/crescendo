import 'dart:io';
import 'reference_note.dart';

/// Represents a fully prepared exercise timeline with an associated reference WAV file.
/// This is the single source of truth for the Exercise Player and Review screens.
class ExercisePlan {
  /// Unique ID for the exercise (e.g. 'five_tone_scales')
  final String exerciseId;

  /// Absolute system path to the synthesized WAV reference audio
  final String wavFilePath;

  /// Sequence of notes to be displayed (pitch highway) and tracked
  final List<ReferenceNote> notes;

  /// Sample rate used for the WAV synthesis (typically 48000)
  final int sampleRate;

  /// Total duration of the exercise in milliseconds
  final int durationMs;

  /// Hash representing the user's vocal range at time of generation
  final String rangeHash;

  /// Hash representing the exercise pattern version (for cache invalidation)
  final String patternHash;

  /// Lead-in time added to the start of the exercise in seconds
  final double leadInSec;

  ExercisePlan({
    required this.exerciseId,
    required this.wavFilePath,
    required this.notes,
    required this.sampleRate,
    required this.durationMs,
    required this.rangeHash,
    required this.patternHash,
    required this.leadInSec,
  });

  File get wavFile => File(wavFilePath);

  /// Helper to convert duration to seconds for clock synchronization
  double get durationSec => durationMs / 1000.0;
}
