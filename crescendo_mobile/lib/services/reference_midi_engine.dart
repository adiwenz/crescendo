import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../models/reference_note.dart';
import '../models/playback_context.dart';
import '../audio/midi_playback_config.dart';
import '../audio/reference_midi_synth.dart';
import '../services/audio_session_service.dart';
import '../services/playback_state_service.dart';

/// Global MIDI engine wrapper for reference audio playback
/// This is a singleton that wraps ReferenceMidiSynth
class ReferenceMidiEngine {
  static final ReferenceMidiEngine _instance = ReferenceMidiEngine._internal();
  factory ReferenceMidiEngine() => _instance;
  ReferenceMidiEngine._internal();

  final ReferenceMidiSynth _synth = ReferenceMidiSynth();
  final PlaybackStateService _playbackState = PlaybackStateService();
  
  bool _ready = false;
  bool _loading = false;
  
  /// Initialize the engine
  Future<void> initialize() async {
    if (_ready) return;
    
    // Ensure ready (load SoundFont)
    await ensureReady(tag: 'initialize');
  }
  
  /// Ensure engine is ready (init + load SoundFont)
  /// Uses mutex to prevent concurrent initialization
  Future<void> ensureReady({String tag = 'ensureReady'}) async {
    if (_ready && !_loading) {
      return;
    }
    
    if (_loading) {
      // Wait for ongoing initialization
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] [$tag] Waiting for ongoing initialization...');
      }
      while (_loading) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return;
    }
    
    await _initAndLoad(tag: tag);
  }
  
  /// Internal: Initialize and load SoundFont
  Future<void> _initAndLoad({String tag = 'initAndLoad', bool force = false}) async {
    if (_loading && !force) return;
    
    _loading = true;
    final startTime = DateTime.now();
    
    try {
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] [$tag] Initializing MIDI engine (force=$force)...');
      }
      
      // Initialize with default config (force reinit if requested)
      await _synth.init(config: MidiPlaybackConfig.exercise(), force: force);
      
      _ready = true;
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] [$tag] Initialization complete (${elapsed}ms)');
      }
    } catch (e) {
      _ready = false;
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] [$tag] Initialization failed: $e');
      }
      rethrow;
    } finally {
      _loading = false;
    }
  }
  
  /// Stop all MIDI playback immediately
  Future<void> stopAll({String tag = 'stopAll'}) async {
    if (kDebugMode) {
      debugPrint('[ReferenceMidiEngine] [$tag] Stopping all MIDI playback');
    }
    
    await _synth.stop();
    _playbackState.clearContext();
  }
  
  /// Play a single MIDI note
  Future<void> playNote(int midi, {int velocity = 100, String tag = 'playNote'}) async {
    await ensureReady(tag: tag);
    // Note: ReferenceMidiSynth doesn't expose playNote directly, so we'd need to add it
    // For now, this is a placeholder
    if (kDebugMode) {
      debugPrint('[ReferenceMidiEngine] [$tag] playNote not yet implemented (midi=$midi)');
    }
  }
  
  /// Stop a single MIDI note
  Future<void> stopNote(int midi, {String tag = 'stopNote'}) async {
    // Note: ReferenceMidiSynth doesn't expose stopNote directly
    if (kDebugMode) {
      debugPrint('[ReferenceMidiEngine] [$tag] stopNote not yet implemented (midi=$midi)');
    }
  }
  
  /// Play a sequence of notes
  Future<void> playSequence({
    required List<ReferenceNote> notes,
    double leadInSec = 0.0,
    required int runId,
    int? startEpochMs,
    MidiPlaybackConfig? config,
    int offsetMs = 0,
    String mode = 'exercise',
  }) async {
    await ensureReady(tag: 'playSequence');
    
    // Apply audio session configuration BEFORE playing (required for route change detection)
    try {
      if (mode == 'exercise') {
        await AudioSessionService.applyExerciseSession(tag: 'playSequence');
      } else {
        await AudioSessionService.applyReviewSession(tag: 'playSequence');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] Error applying audio session: $e');
      }
    }
    
    // Register playback context
    final context = mode == 'exercise'
        ? PlaybackContext.exercise(
            notes: notes,
            currentTimeSec: 0.0, // Will be updated as playback progresses
            leadInSec: leadInSec,
            runId: runId,
            startEpochMs: startEpochMs,
            offsetMs: offsetMs,
            config: config,
          )
        : PlaybackContext.review(
            notes: notes,
            currentTimeSec: 0.0,
            leadInSec: leadInSec,
            runId: runId,
            startEpochMs: startEpochMs,
            offsetMs: offsetMs,
            config: config,
          );
    
    _playbackState.registerContext(context);
    
    // Play sequence using synth
    await _synth.playSequence(
      notes: notes,
      leadInSec: leadInSec,
      runId: runId,
      startEpochMs: startEpochMs,
      config: config,
      offsetMs: offsetMs,
    );
  }
  
  /// Recover MIDI engine after route change
  /// This method reinitializes the MIDI engine and resumes playback
  Future<void> recoverAfterRouteChange({required PlaybackContext context}) async {
    final recoverStartTime = DateTime.now();
    
    try {
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] [recoverAfterRouteChange] Starting MIDI recovery...');
        debugPrint('[ReferenceMidiEngine] [recoverAfterRouteChange] Context: mode=${context.mode}, runId=${context.runId}, currentTime=${context.currentTimeSec.toStringAsFixed(3)}s');
      }
      
      // Step 1: Mark MIDI engine as needing rebuild
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] [recoverAfterRouteChange] Step 1: Marking engine for rebuild...');
      }
      _synth.markEngineRebuildNeeded();
      
      // Step 2: Force reinitialize MIDI engine (unload + reload soundfont)
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] [recoverAfterRouteChange] Step 2: Reinitializing MIDI engine (force=true)...');
      }
      final reinitStartTime = DateTime.now();
      _ready = false; // Force reinitialization
      await _initAndLoad(tag: 'recoverAfterRouteChange-reinit', force: true);
      final reinitElapsed = DateTime.now().difference(reinitStartTime).inMilliseconds;
      
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] [recoverAfterRouteChange] MIDI engine reinit complete (${reinitElapsed}ms)');
      }
      
      // Step 3: Warm up engine
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] [recoverAfterRouteChange] Step 3: Warming up MIDI engine...');
      }
      await _warmUpEngine();
      
      // Step 4: Get current position from playback state (may have been updated)
      final currentPositionSec = _playbackState.currentContext?.currentTimeSec ?? context.currentTimeSec;
      
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] [recoverAfterRouteChange] Step 4: Current position: ${currentPositionSec.toStringAsFixed(3)}s (context had ${context.currentTimeSec.toStringAsFixed(3)}s)');
      }
      
      // Step 5: Filter notes that should play from current position
      final notesToPlay = context.notes.where((note) {
        return note.endSec > currentPositionSec;
      }).toList();
      
      if (notesToPlay.isEmpty) {
        if (kDebugMode) {
          debugPrint('[ReferenceMidiEngine] [recoverAfterRouteChange] No notes to resume (all notes already played)');
        }
        return;
      }
      
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] [recoverAfterRouteChange] Step 5: Found ${notesToPlay.length} notes to resume (from ${context.notes.length} total)');
      }
      
      // Step 6: Adjust note times to be relative to current position
      final adjustedNotes = notesToPlay.map((note) {
        final adjustedStart = (note.startSec - currentPositionSec).clamp(0.0, double.infinity);
        final adjustedEnd = note.endSec - currentPositionSec;
        return ReferenceNote(
          startSec: adjustedStart,
          endSec: adjustedEnd,
          midi: note.midi,
          lyric: note.lyric,
          isGlideStart: note.isGlideStart,
          isGlideEnd: note.isGlideEnd,
          glideEndMidi: note.glideEndMidi,
        );
      }).toList();
      
      // Step 7: Bump runId to cancel old timers/notes
      final newRunId = context.runId + 1000; // Use large increment to avoid conflicts
      final resumeStartEpoch = DateTime.now().millisecondsSinceEpoch;
      
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] [recoverAfterRouteChange] Step 6: Bumping runId: ${context.runId} → $newRunId');
        debugPrint('[ReferenceMidiEngine] [recoverAfterRouteChange] Step 7: Resuming playback from position ${currentPositionSec.toStringAsFixed(3)}s with ${adjustedNotes.length} notes...');
      }
      
      // Step 8: Resume playback with adjusted notes and new runId
      await playSequence(
        notes: adjustedNotes,
        leadInSec: 0.0, // No lead-in for resume
        runId: newRunId,
        startEpochMs: resumeStartEpoch,
        config: context.config,
        offsetMs: context.offsetMs,
        mode: context.mode,
      );
      
      final recoverElapsed = DateTime.now().difference(recoverStartTime).inMilliseconds;
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] [recoverAfterRouteChange] ✅ MIDI recovery complete (${recoverElapsed}ms total)');
        debugPrint('[ReferenceMidiEngine] [recoverAfterRouteChange] Resume playback from t=${currentPositionSec.toStringAsFixed(3)}s, ${adjustedNotes.length} notes scheduled, runId=$newRunId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] [recoverAfterRouteChange] ❌ ERROR during MIDI recovery: $e');
      }
      rethrow;
    }
  }
  
  /// Resume playback after route change (legacy method name, now calls recoverAfterRouteChange)
  @Deprecated('Use recoverAfterRouteChange instead')
  Future<void> resumeAfterRouteChange({required PlaybackContext context}) async {
    return recoverAfterRouteChange(context: context);
  }
  
  /// Warm up the MIDI engine after reinit
  Future<void> _warmUpEngine() async {
    try {
      // Play a very low velocity note and stop it quickly
      // This "wakes up" the MIDI engine
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] Warming up MIDI engine...');
      }
      
      // Note: This requires adding a playNote/stopNote API to ReferenceMidiSynth
      // For now, we'll skip warmup or use a workaround
      await Future.delayed(const Duration(milliseconds: 50));
      
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] Warmup complete');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] Warmup failed (non-critical): $e');
      }
    }
  }

  
  /// Dispose the engine
  void dispose() {
    // Cleanup if needed
  }
  
  /// Update playback position (for tracking current time)
  void updatePosition(double currentTimeSec, {int? runId}) {
    _playbackState.updatePosition(currentTimeSec, runId: runId);
  }
  
  /// Clear playback context (when playback stops normally)
  void clearContext({int? runId}) {
    _playbackState.clearContext(runId: runId);
  }
}
