import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../models/playback_context.dart';

/// Global service to track current MIDI playback context
/// Used to resume playback after route changes
class PlaybackStateService {
  static final PlaybackStateService _instance = PlaybackStateService._internal();
  factory PlaybackStateService() => _instance;
  PlaybackStateService._internal();

  PlaybackContext? _currentContext;
  int _currentRunId = 0;

  /// Get current playback context
  PlaybackContext? get currentContext => _currentContext;

  /// Get current run ID
  int get currentRunId => _currentRunId;

  /// Check if playback is currently active
  bool get isPlaying => _currentContext != null;

  /// Register current playback context
  void registerContext(PlaybackContext context) {
    if (kDebugMode) {
      debugPrint('[PlaybackStateService] Registering context: $context');
    }
    _currentContext = context;
    _currentRunId = context.runId;
  }

  /// Clear current playback context (when playback stops)
  void clearContext({int? runId}) {
    if (kDebugMode) {
      debugPrint('[PlaybackStateService] Clearing context (runId=$runId, currentRunId=$_currentRunId)');
    }
    if (runId == null || runId == _currentRunId) {
      _currentContext = null;
    }
  }

  /// Update current playback position (for resuming after route change)
  void updatePosition(double currentTimeSec, {int? runId}) {
    if (_currentContext != null && (runId == null || runId == _currentContext!.runId)) {
      // Create updated context with new position
      _currentContext = PlaybackContext(
        mode: _currentContext!.mode,
        notes: _currentContext!.notes,
        currentTimeSec: currentTimeSec,
        leadInSec: _currentContext!.leadInSec,
        config: _currentContext!.config,
        runId: _currentContext!.runId,
        startEpochMs: _currentContext!.startEpochMs,
        offsetMs: _currentContext!.offsetMs,
      );
      if (kDebugMode && (currentTimeSec * 1000).round() % 1000 == 0) {
        // Log every second for debugging
        debugPrint('[PlaybackStateService] Position updated: ${currentTimeSec.toStringAsFixed(2)}s');
      }
    }
  }

  /// Get context for resuming playback (validates runId)
  PlaybackContext? getContextForResume(int runId) {
    if (_currentContext == null) {
      if (kDebugMode) {
        debugPrint('[PlaybackStateService] No context available for resume');
      }
      return null;
    }
    
    if (!_currentContext!.isValidForRunId(runId)) {
      if (kDebugMode) {
        debugPrint('[PlaybackStateService] Context stale (runId=$runId, contextRunId=${_currentContext!.runId})');
      }
      return null;
    }
    
    return _currentContext;
  }
}
