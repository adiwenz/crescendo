import 'dart:async';
import 'package:flutter/foundation.dart';
import 'audio_synth_service.dart';
import 'recording_service.dart';
import '../utils/performance_clock.dart';

/// Centralized controller to manage audio lifecycle during exercise playback.
/// Ensures all audio resources are stopped and released cleanly during navigation.
class ExerciseAudioController {
  final AudioSynthService synth;
  final RecordingService? recording;
  final PerformanceClock clock;

  bool _isShuttingDown = false;
  bool get isShuttingDown => _isShuttingDown;

  ExerciseAudioController({
    required this.synth,
    this.recording,
    required this.clock,
  });

  /// Stop all audio playback and recording instantly.
  /// Enforces a clean shutdown sequence to prevent iOS audio glitches.
  /// Returns the RecordingStopResult if recording was active.
  Future<RecordingStopResult?> stopAndRelease() async {
    if (_isShuttingDown) return null;
    _isShuttingDown = true;
    
    final startTime = DateTime.now();
    debugPrint('[AudioController] Starting stopAndRelease teardown...');
    RecordingStopResult? result;

    try {
      // Phase 1: Immediate mute to prevent buzzing/glitches
      debugPrint('[AudioController] P1: Muting player');
      await synth.player.setVolume(0.0);
      
      // Phase 2: Stop engines and await completion
      debugPrint('[AudioController] P2: Stopping engines');
      final synthStop = synth.stop();
      final recordingStop = recording?.stop();
      
      final results = await Future.wait([
        synthStop,
        if (recordingStop != null) recordingStop,
      ]);
      
      if (recordingStop != null && results.length > 1) {
        result = results[1] as RecordingStopResult?;
      }
      
      // Phase 3: Pause clock and release resources
      debugPrint('[AudioController] P3: Pausing clock');
      clock.pause();
      
      final elapsed = DateTime.now().difference(startTime);
      debugPrint('[AudioController] Teardown complete in ${elapsed.inMilliseconds}ms');
    } catch (e) {
      debugPrint('[AudioController] Error during teardown: $e');
    }
    return result;
  }

  /// Reset the controller for a new run
  void reset() {
    _isShuttingDown = false;
  }

  /// Partial dispose (full dispose is usually handled by individual services or on app exit)
  void dispose() {
    // Services are usually long-lived singletons or owned by the screen dispose
    // But we ensure clock is paused
    clock.pause();
  }
}
