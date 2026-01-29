import '../models/reference_note.dart';
import '../audio/midi_playback_config.dart';

/// Context for resuming MIDI playback after route changes
class PlaybackContext {
  /// Playback mode: "exercise" or "review"
  final String mode;
  
  /// List of notes to play
  final List<ReferenceNote> notes;
  
  /// Current playback position in seconds (visual/audio position)
  final double currentTimeSec;
  
  /// Lead-in time in seconds (time before first note)
  final double leadInSec;
  
  /// MIDI playback configuration
  final MidiPlaybackConfig config;
  
  /// Current run ID (for guarding against stale resumes)
  final int runId;
  
  /// Optional: start epoch timestamp (for timer-based scheduling)
  final int? startEpochMs;
  
  /// Optional: manual offset in milliseconds (for sync compensation)
  final int offsetMs;

  const PlaybackContext({
    required this.mode,
    required this.notes,
    required this.currentTimeSec,
    required this.leadInSec,
    required this.config,
    required this.runId,
    this.startEpochMs,
    this.offsetMs = 0,
  });

  /// Create a context for exercise playback
  factory PlaybackContext.exercise({
    required List<ReferenceNote> notes,
    required double currentTimeSec,
    required double leadInSec,
    required int runId,
    int? startEpochMs,
    int offsetMs = 0,
    MidiPlaybackConfig? config,
  }) {
    return PlaybackContext(
      mode: 'exercise',
      notes: notes,
      currentTimeSec: currentTimeSec,
      leadInSec: leadInSec,
      config: config ?? MidiPlaybackConfig.exercise(),
      runId: runId,
      startEpochMs: startEpochMs,
      offsetMs: offsetMs,
    );
  }

  /// Create a context for review playback
  factory PlaybackContext.review({
    required List<ReferenceNote> notes,
    required double currentTimeSec,
    required double leadInSec,
    required int runId,
    int? startEpochMs,
    int offsetMs = 0,
    MidiPlaybackConfig? config,
  }) {
    return PlaybackContext(
      mode: 'review',
      notes: notes,
      currentTimeSec: currentTimeSec,
      leadInSec: leadInSec,
      config: config ?? MidiPlaybackConfig.review(),
      runId: runId,
      startEpochMs: startEpochMs,
      offsetMs: offsetMs,
    );
  }

  /// Check if this context is still valid (not stale)
  bool isValidForRunId(int currentRunId) {
    return runId == currentRunId;
  }

  @override
  String toString() {
    return 'PlaybackContext(mode=$mode, notes=${notes.length}, currentTime=${currentTimeSec.toStringAsFixed(2)}s, runId=$runId)';
  }
}
