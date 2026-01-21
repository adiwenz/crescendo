import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../models/reference_note.dart';
import '../models/playback_context.dart';
import '../audio/midi_playback_config.dart';
import '../audio/reference_midi_synth.dart';
import '../services/audio_session_service.dart';
import '../services/playback_state_service.dart';
import '../services/audio_route_service.dart';

/// Global MIDI engine wrapper that handles route changes and automatic resumption
/// This is a singleton that wraps ReferenceMidiSynth and adds route change resilience
class ReferenceMidiEngine {
  static final ReferenceMidiEngine _instance = ReferenceMidiEngine._internal();
  factory ReferenceMidiEngine() => _instance;
  ReferenceMidiEngine._internal();

  final ReferenceMidiSynth _synth = ReferenceMidiSynth();
  final PlaybackStateService _playbackState = PlaybackStateService();
  final AudioRouteService _audioRoute = AudioRouteService();
  
  bool _ready = false;
  bool _loading = false;
  StreamSubscription<AudioOutputType>? _routeSubscription;
  
  // Route change handling
  Timer? _routeChangeDebounceTimer;
  bool _isHandlingRouteChange = false;
  
  /// Initialize the engine and set up route change listener
  Future<void> initialize() async {
    if (_ready) return;
    
            // Initialize audio route service (uses flutter_headset_detector)
            await _audioRoute.initialize();

            // Subscribe to route changes from flutter_headset_detector
            _routeSubscription?.cancel();
            _routeSubscription = _audioRoute.outputStream.listen(_handleRouteChanged);

            if (kDebugMode) {
              debugPrint('[ReferenceMidiEngine] Initialized with flutter_headset_detector route detection');
            }
    
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
  Future<void> _initAndLoad({String tag = 'initAndLoad'}) async {
    if (_loading) return;
    
    _loading = true;
    final startTime = DateTime.now();
    
    try {
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] [$tag] Initializing MIDI engine...');
      }
      
      // Initialize with default config
      await _synth.init(config: MidiPlaybackConfig.exercise(), force: false);
      
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
  
  /// Resume playback after route change
  Future<void> resumeAfterRouteChange({required PlaybackContext context}) async {
    if (_isHandlingRouteChange) {
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] Route change already being handled, skipping resume');
      }
      return;
    }
    
    _isHandlingRouteChange = true;
    final resumeStartTime = DateTime.now();
    
    try {
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] Resuming playback after route change: $context');
      }
      
      // Step 1: Stop all current playback
      await stopAll(tag: 'resumeAfterRouteChange-stop');
      
      // Step 2: Wait for route stabilization (debounce)
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Step 3: Re-initialize MIDI engine
      if (kDebugMode) {
        debugPrint('[AudioRoute] Restarting MIDI engine after route change');
      }
      final reinitStartTime = DateTime.now();
      await _initAndLoad(tag: 'resumeAfterRouteChange-reinit');
      final reinitElapsed = DateTime.now().difference(reinitStartTime).inMilliseconds;
      
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] Reinit complete (${reinitElapsed}ms)');
      }
      
      // Step 4: Warm up engine (play a silent/low note)
      await _warmUpEngine();
      
      // Step 5: Get current position from playback state (may have been updated)
      final currentPositionSec = _playbackState.currentContext?.currentTimeSec ?? context.currentTimeSec;
      
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] Resuming from position: ${currentPositionSec.toStringAsFixed(3)}s (context had ${context.currentTimeSec.toStringAsFixed(3)}s)');
      }
      
      // Step 6: Filter notes that should play from current position
      final notesToPlay = context.notes.where((note) {
        return note.endSec > currentPositionSec;
      }).toList();
      
      if (notesToPlay.isEmpty) {
        if (kDebugMode) {
          debugPrint('[ReferenceMidiEngine] No notes to resume (all notes already played)');
        }
        return;
      }
      
      // Step 7: Adjust note times to be relative to current position
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
      
      // Step 8: Resume playback with adjusted notes
      final resumeRunId = context.runId;
      final resumeStartEpoch = DateTime.now().millisecondsSinceEpoch;
      
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] Resuming ${adjustedNotes.length} notes from position ${currentPositionSec.toStringAsFixed(3)}s');
      }
      
      await playSequence(
        notes: adjustedNotes,
        leadInSec: 0.0, // No lead-in for resume
        runId: resumeRunId,
        startEpochMs: resumeStartEpoch,
        config: context.config,
        offsetMs: context.offsetMs,
        mode: context.mode,
      );
      
      final resumeElapsed = DateTime.now().difference(resumeStartTime).inMilliseconds;
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] Resume complete (${resumeElapsed}ms total)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] Error resuming playback: $e');
      }
    } finally {
      _isHandlingRouteChange = false;
    }
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
  
          /// Handle route change event from flutter_headset_detector (debounced)
  void _handleRouteChanged(AudioOutputType newOutput) {
    if (kDebugMode) {
      debugPrint('[ReferenceMidiEngine] Route changed → $newOutput (hasHeadphones=${_audioRoute.hasHeadphones})');
    }
    
    // Cancel existing debounce timer
    _routeChangeDebounceTimer?.cancel();
    
    // Debounce route changes (wait 150ms for stabilization)
    _routeChangeDebounceTimer = Timer(const Duration(milliseconds: 150), () async {
      await _processRouteChange();
    });
  }
  
  /// Process route change (called after debounce)
  Future<void> _processRouteChange() async {
    final hasHeadphones = _audioRoute.hasHeadphones;
    
    if (kDebugMode) {
      debugPrint('[ReferenceMidiEngine] Processing route change: output=${_audioRoute.currentOutput}, hasHeadphones=$hasHeadphones');
    }
    
    // Get current playback context (with latest position)
    final context = _playbackState.currentContext;
    if (context == null) {
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] No active playback, skipping resume');
      }
      return;
    }
    
    // Step 1: Stop all MIDI immediately
    await stopAll(tag: 'routeChange-stop');
    
    // Step 2: Re-apply audio session
    try {
      if (context.mode == 'exercise') {
        await AudioSessionService.applyExerciseSession(tag: 'routeChange');
      } else {
        await AudioSessionService.applyReviewSession(tag: 'routeChange');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] Error applying audio session: $e');
      }
    }
    
    // Step 3: Wait for route stabilization
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Step 4: Get updated context with latest position (in case position was updated during delay)
    final updatedContext = _playbackState.currentContext;
    if (updatedContext != null && updatedContext.runId == context.runId) {
      // Step 5: Resume playback with updated context
      await resumeAfterRouteChange(context: updatedContext);
    } else {
      if (kDebugMode) {
        debugPrint('[ReferenceMidiEngine] Context changed during route change, skipping resume');
      }
    }
  }
  
  /// Dispose the engine
  void dispose() {
    _routeSubscription?.cancel();
    _routeSubscription = null;
    _routeChangeDebounceTimer?.cancel();
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
