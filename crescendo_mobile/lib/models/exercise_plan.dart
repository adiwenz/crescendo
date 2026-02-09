import 'dart:io';
import 'reference_note.dart';

/// Represents a fully prepared exercise timeline with an associated reference WAV file.
/// This is the single source of truth for the Exercise Player and Review screens.
class ExercisePlan {
  /// Unique ID for the exercise (e.g. 'five_tone_scales')
  final String id;

  /// Display title for the exercise
  final String title;

  /// Key label (e.g. 'C Major')
  final String keyLabel;

  /// Absolute system path to the synthesized WAV reference audio
  final String wavFilePath;

  /// Sequence of notes to be displayed (pitch highway) and tracked
  final List<ReferenceNote> notes;

  /// Sequence of harmony notes (chords) for background audio
  final List<ReferenceNote> harmonyNotes;

  /// Sample rate used for the WAV synthesis (typically 48000)
  final int sampleRate;

  /// Total duration of the exercise in milliseconds
  final int durationMs;

  /// Gap between notes in seconds
  final double gapSec;

  /// BPM for the exercise (if applicable)
  final int? bpm;

  /// Offset in ms for scoring
  final int scoreOffsetMs;

  /// Hash representing the user's vocal range at time of generation
  final String rangeHash;

  /// Hash representing the exercise pattern version (for cache invalidation)
  final String patternHash;

  /// Lead-in time added to the start of the exercise in seconds
  final double leadInSec;

  ExercisePlan({
    required this.id,
    required this.title,
    required this.keyLabel,
    required this.wavFilePath,
    required this.notes,
    this.harmonyNotes = const [],
    required this.sampleRate,
    required this.durationMs,
    this.gapSec = 0.0,
    this.bpm,
    this.scoreOffsetMs = 0,
    required this.rangeHash,
    required this.patternHash,
    required this.leadInSec,
  });

  File get wavFile => File(wavFilePath);

  /// Helper to convert duration to seconds for clock synchronization
  double get durationSec => durationMs / 1000.0;
  
  /// Backward compatibility for code using exerciseId
  String get exerciseId => id;

  factory ExercisePlan.empty() {
    return ExercisePlan(
      id: '',
      title: '',
      keyLabel: '',
      wavFilePath: '',
      notes: const [],
      sampleRate: 44100,
      durationMs: 0,
      rangeHash: '',
      patternHash: '',
      leadInSec: 0,
    );
  }

  ExercisePlan copyWith({
    String? id,
    String? title,
    String? keyLabel,
    String? wavFilePath,
    List<ReferenceNote>? notes,
    List<ReferenceNote>? harmonyNotes,
    int? sampleRate,
    int? durationMs,
    double? gapSec,
    int? bpm,
    int? scoreOffsetMs,
    String? rangeHash,
    String? patternHash,
    double? leadInSec,
    double? durationSec, // Allow passing seconds directly or use milliseconds
  }) {
    return ExercisePlan(
      id: id ?? this.id,
      title: title ?? this.title,
      keyLabel: keyLabel ?? this.keyLabel,
      wavFilePath: wavFilePath ?? this.wavFilePath,
      notes: notes ?? this.notes,
      harmonyNotes: harmonyNotes ?? this.harmonyNotes,
      sampleRate: sampleRate ?? this.sampleRate,
      durationMs: durationMs ?? (durationSec != null ? (durationSec * 1000).round() : this.durationMs),
      gapSec: gapSec ?? this.gapSec,
      bpm: bpm ?? this.bpm,
      scoreOffsetMs: scoreOffsetMs ?? this.scoreOffsetMs,
      rangeHash: rangeHash ?? this.rangeHash,
      patternHash: patternHash ?? this.patternHash,
      leadInSec: leadInSec ?? this.leadInSec,
    );
  }
}
