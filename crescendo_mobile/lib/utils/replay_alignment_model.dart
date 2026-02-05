import 'package:flutter/foundation.dart';

/// Handles the complex time mapping between Recorded Audio, Reference Audio,
/// and the Exercise Timeline (Visuals).
/// 
/// Core concept:
/// - [exerciseTime]: The sovereign timeline defined by the ExercisePlan. 
///   0.0 is the start of the reference WAV file (which includes lead-in silence).
///   Notes typically start at `leadIn + chirpOffset`.
/// 
/// - [micOffsetSec]: The time delaying the microphone relative to the reference.
///   Positive means Mic is LATE (e.g. recorded chirp appears after Ref chirp).
///   Negative means Mic is EARLY.
/// 
/// - [micTime]: Time relative to the start of the recording stream/files.
class ReplayAlignmentModel {
  /// The measured offset between Reference (0.0) and Recording (0.0).
  /// Derived from [AudioOffsetResult].
  /// Positive = Mic is LATE.
  final double micOffsetSec;

  /// Duration of the lead-in silence included in the Reference WAV.
  /// Used for context/logging, though mapping is primarily offset-based.
  final double leadInSec;

  const ReplayAlignmentModel({
    required this.micOffsetSec,
    this.leadInSec = 0.0,
  });

  /// Maps the current position of the Reference Audio Player to Exercise Time.
  /// Since the Reference WAV *defines* the timeline, this is usually 1:1.
  double refPositionToExerciseTime(double refPositionSec) {
    return refPositionSec;
  }

  /// Maps a timestamp from the Recorded Pitch Stream to Exercise Time.
  /// 
  /// If Mic is LATE (offset > 0) by 0.5s:
  /// A note sung at 1.5s in Mic corresponds to 1.0s in Ref.
  /// So: t_ref = t_mic - offset.
  double micTimeToExerciseTime(double micTimeSec) {
    return micTimeSec - micOffsetSec;
  }
}
