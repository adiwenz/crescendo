import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';

import '../../models/last_take.dart';
import '../../models/pitch_highway_difficulty.dart';
import '../../models/reference_note.dart';
import '../../models/vocal_exercise.dart';
import '../../models/siren_path.dart';
import '../../services/audio_synth_service.dart';
import '../../services/reference_midi_engine.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../audio/midi_playback_config.dart';
import '../../services/transposed_exercise_builder.dart';
import '../../services/vocal_range_service.dart';
import '../../utils/pitch_highway_tempo.dart';
import '../../utils/pitch_math.dart';
import '../../utils/performance_clock.dart';
import '../../utils/exercise_constants.dart';
import '../../debug/debug_log.dart' show DebugLog, LogCat;
import '../../services/sync_diagnostic_service.dart';
import '../../services/audio_session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/pitch_contour_painter.dart';
import '../widgets/pitch_highway_painter.dart';

class PitchHighwayReviewScreen extends StatefulWidget {
  final VocalExercise exercise;
  final LastTake lastTake;
  final double startTimeSec;

  const PitchHighwayReviewScreen({
    super.key,
    required this.exercise,
    required this.lastTake,
    this.startTimeSec = 0.0,
  });

  @override
  State<PitchHighwayReviewScreen> createState() => _PitchHighwayReviewScreenState();
}

class _PitchHighwayReviewScreenState extends State<PitchHighwayReviewScreen>
    with SingleTickerProviderStateMixin {
  // Enable mixing mode to play both recorded audio and reference notes simultaneously
  final AudioSynthService _synth = AudioSynthService(enableMixing: true);
  final ReferenceMidiEngine _midiEngine = ReferenceMidiEngine();
  final VocalRangeService _vocalRangeService = VocalRangeService();
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  final PerformanceClock _clock = PerformanceClock();
  Ticker? _ticker;
  bool _playing = false;
  StreamSubscription<Duration>? _audioPosSub;
  StreamSubscription<void>? _audioCompleteSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  Timer? _positionWatchdog;
  Timer? _midiOnlyTimer; // Timer for MIDI-only playback when there's no recorded audio
  int? _lastPositionUpdateMs;
  double? _audioPositionSec;
  bool _audioStarted = false;
  List<ReferenceNote> _notes = const [];
  SirenPath? _sirenVisualPath; // Visual path for Sirens (separate from audio notes)
  double _durationSec = 1.0;
  // Use shared constant for lead-in time
  static const double _leadInSec = ExerciseConstants.leadInSec;
  bool _loggedGraphInfo = false;
  late final double _pixelsPerSecond;
  
  // Preload state
  bool _preloadComplete = false;
  bool _preloading = false;
  String? _referenceAudioPath;
  String? _recordedAudioPath;
  DateTime? _playbackStartEpoch; // Exact moment playback truly starts
  int _lastSyncLogTime = 0;
  int _reviewRunId = 0; // Run ID for review MIDI playback
  int? _midiOnlyStartTime; // Start time for MIDI-only timer (set after MIDI sequence is initialized)
  
  // Sync compensation (debug only)
  static const bool kEnableSyncCompensation = true; // Set to false to disable compensation
  int? _syncOffsetMs; // Cached sync offset from diagnostic
  int _manualOffsetMs = 0; // Manual offset adjustment (can be positive or negative)
  bool _compensationEnabled = true; // Toggle to enable/disable compensation (default: enabled)

  @override
  void initState() {
    super.initState();
    
    // Initialize MIDI engine (sets up route change listeners automatically)
    unawaited(_midiEngine.initialize());
    
    // Set debug context
    _reviewRunId++;
    DebugLog.setContext(
      runId: _reviewRunId,
      exerciseId: widget.exercise.id,
      mode: 'replay',
    );
    
    final difficulty =
        pitchHighwayDifficultyFromName(widget.lastTake.pitchDifficulty) ??
            PitchHighwayDifficulty.medium;
    _pixelsPerSecond = PitchHighwayTempo.pixelsPerSecondFor(difficulty);
    _ticker = createTicker(_onTick);
    _clock.setAudioPositionProvider(() => _audioPositionSec);
    // In review mode, audio position is already accurate (from playback), so no latency compensation needed
    _clock.setLatencyCompensationMs(0);
    _time.value = widget.startTimeSec;
    
    // Load sync offset for compensation (debug only)
    if (kDebugMode && kEnableSyncCompensation) {
      _loadSyncOffset();
    }
    
    // Log replay start
    unawaited(_logReplayStart());
    
    _preloadEverything(difficulty);
  }
  
  /// Log replay start
  Future<void> _logReplayStart() async {
    DebugLog.event(
      LogCat.replay,
      'replay_start',
      runId: _reviewRunId,
      fields: {
        'recordingDurationSec': widget.lastTake.durationSec,
        'recordedFilePath': widget.lastTake.audioPath,
        'willPlayRecording': _recordedAudioPath != null,
        'willPlayReference': _notes.isNotEmpty,
        'initialSeekSec': widget.startTimeSec,
      },
    );
  }
  
  /// Preload everything before allowing playback
  Future<void> _preloadEverything(PitchHighwayDifficulty difficulty) async {
    if (_preloading) return;
    _preloading = true;
    
    final tapTime = DateTime.now().millisecondsSinceEpoch;
    if (kDebugMode) {
      debugPrint('[Review Preload] tapTime=$tapTime (preload started)');
    }
    
    // Step 1: Load transposed notes
    await _loadTransposedNotes(difficulty);
    
    // Step 2: Check recorded audio (fast file check)
    final audioPath = widget.lastTake.audioPath;
    if (audioPath != null && audioPath.isNotEmpty) {
      final file = File(audioPath);
      if (await file.exists()) {
        _recordedAudioPath = audioPath;
        if (kDebugMode) {
          debugPrint('[Review Preload] Recorded audio found: ${_recordedAudioPath}');
        }
      }
    }
    
    // Step 3: Initialize MIDI engine (fast, no WAV rendering needed)
    // This is much faster than WAV rendering and is what we actually use for playback
    await _midiEngine.ensureReady(tag: 'review-preload');
    
    // Step 4: Skip WAV rendering - we use ReferenceMidiSynth for real-time MIDI playback
    // WAV rendering was causing 10+ second delays. MIDI synth is instant.
    // Only render WAV in background if needed for mixing (but don't block on it)
    if (_notes.isNotEmpty) {
      // Render WAV asynchronously in background (non-blocking)
      unawaited(_renderReferenceAudioInBackground());
    }
    
    final preloadCompleteTime = DateTime.now().millisecondsSinceEpoch;
    if (kDebugMode) {
      debugPrint('[Review Preload] preloadCompleteTime=$preloadCompleteTime (preload finished, took ${preloadCompleteTime - tapTime}ms)');
    }
    
    if (mounted) {
      setState(() {
        _preloadComplete = true;
        _preloading = false;
      });
      
      // Auto-start playback immediately once preload is complete
      // Use SchedulerBinding to ensure this runs after the frame is built
      if (_notes.isNotEmpty && !_playing) {
        if (kDebugMode) {
          debugPrint('[Review] Preload complete, attempting auto-start: notes=${_notes.length}, playing=$_playing');
        }
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_playing && _preloadComplete && _notes.isNotEmpty) {
            if (kDebugMode) {
              debugPrint('[Review] Auto-starting playback: notes=${_notes.length}, preloadComplete=$_preloadComplete');
            }
            _start();
          } else if (kDebugMode) {
            debugPrint('[Review] Auto-start skipped: mounted=$mounted, playing=$_playing, preloadComplete=$_preloadComplete, notesEmpty=${_notes.isEmpty}');
          }
        });
      } else if (kDebugMode && _notes.isEmpty) {
        debugPrint('[Review] WARNING: Preload complete but notes are empty!');
      }
    }
  }
  
  /// Render reference audio in background (non-blocking)
  /// This is only used as a fallback - MIDI synth is the primary playback method
  Future<void> _renderReferenceAudioInBackground() async {
    try {
      _referenceAudioPath = await _synth.renderReferenceNotes(_notes);
      if (kDebugMode) {
        debugPrint('[Review Preload] Reference audio rendered in background (WAV fallback): ${_referenceAudioPath}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Review Preload] Background WAV rendering error (non-fatal): $e');
      }
    }
  }

  /// Filter and adjust notes for segment playback
  /// Returns notes that start at or after startOffsetSec, with their timing adjusted
  List<ReferenceNote> _filterAndAdjustNotesForSegment(List<ReferenceNote> allNotes, double startOffsetSec) {
    if (startOffsetSec <= 0) {
      // No offset - return all notes as-is
      return allNotes;
    }
    
    // Filter notes that start at or after the segment start time
    // Adjust their startSec and endSec to be relative to the playback start (0.0)
    final filteredNotes = <ReferenceNote>[];
    for (final note in allNotes) {
      // Only include notes that start at or after startOffsetSec
      if (note.startSec >= startOffsetSec) {
        // Adjust timing to be relative to playback start (subtract startOffsetSec)
        filteredNotes.add(ReferenceNote(
          midi: note.midi,
          startSec: note.startSec - startOffsetSec,
          endSec: note.endSec - startOffsetSec,
          isGlideStart: note.isGlideStart,
          isGlideEnd: note.isGlideEnd,
        ));
      } else if (note.endSec > startOffsetSec) {
        // Note starts before segment but ends during segment - include it but clip the start
        filteredNotes.add(ReferenceNote(
          midi: note.midi,
          startSec: 0.0, // Start immediately (note was already playing)
          endSec: note.endSec - startOffsetSec,
          isGlideStart: note.isGlideStart,
          isGlideEnd: note.isGlideEnd,
        ));
      }
    }
    
    if (kDebugMode && startOffsetSec > 0) {
      debugPrint('[Review] Filtered notes for segment: ${allNotes.length} -> ${filteredNotes.length} '
          '(startOffsetSec=$startOffsetSec)');
      if (filteredNotes.isNotEmpty) {
        debugPrint('[Review] First filtered note: MIDI=${filteredNotes.first.midi}, '
            'startSec=${filteredNotes.first.startSec.toStringAsFixed(2)}');
      }
    }
    
    return filteredNotes;
  }

  /// Load sync offset from SharedPreferences (debug only)
  Future<void> _loadSyncOffset() async {
    if (!kDebugMode || !kEnableSyncCompensation) return;
    
    try {
      final offset = await SyncDiagnosticService.getSavedOffset();
      if (mounted) {
        setState(() {
          _syncOffsetMs = offset;
        });
        if (offset != null) {
          debugPrint('[Review] Loaded sync offset: ${offset}ms');
        }
      }
    } catch (e) {
      debugPrint('[Review] Error loading sync offset: $e');
    }
  }

  Future<void> _loadTransposedNotes(PitchHighwayDifficulty difficulty) async {
    final (lowestMidi, highestMidi) = await _vocalRangeService.getRange();
    
    // Special handling for Sirens: use buildSirensWithVisualPath to get both audio notes and visual path
    final List<ReferenceNote> notes;
    SirenPath? sirenPath;
    if (widget.exercise.id == 'sirens') {
      final sirenResult = TransposedExerciseBuilder.buildSirensWithVisualPath(
        exercise: widget.exercise,
        lowestMidi: lowestMidi,
        highestMidi: highestMidi,
        leadInSec: _leadInSec,
        difficulty: difficulty,
      );
      notes = sirenResult.audioNotes; // Get the 3 audio notes for playback
      sirenPath = sirenResult.visualPath; // Get the visual bell curve path
    } else {
      notes = TransposedExerciseBuilder.buildTransposedSequence(
        exercise: widget.exercise,
        lowestMidi: lowestMidi,
        highestMidi: highestMidi,
        leadInSec: _leadInSec,
        difficulty: difficulty,
      );
      sirenPath = null;
    }
    
    if (mounted) {
      setState(() {
        _notes = notes;
        _sirenVisualPath = sirenPath; // Store visual path for Sirens
        _durationSec = _computeDuration(notes);
      });
      
      // Try to auto-start if preload is already complete
      // Otherwise, preload completion will trigger auto-start
      if (notes.isNotEmpty && !_playing && _preloadComplete) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_playing && _notes.isNotEmpty && _preloadComplete) {
            if (kDebugMode) {
              debugPrint('[Review] Auto-starting from notes loaded: notes=${_notes.length}');
            }
            _start();
          }
        });
      }
    }
  }

  // Route change handlers removed - ReferenceMidiEngine handles route changes automatically
  // The engine will automatically resume playback using the registered playback context
  
  @override
  void dispose() {
    DebugLog.event(
      LogCat.replay,
      'replay_dispose',
      runId: _reviewRunId,
      fields: {
        'wasPlaying': _playing,
      },
    );
    DebugLog.resetContext();
    
    // Dispose route change listeners
    // Audio session service doesn't need disposal
    
    _ticker?.dispose();
    _audioPosSub?.cancel();
    _audioCompleteSub?.cancel();
    _playerStateSub?.cancel();
    _positionWatchdog?.cancel();
    _synth.stop();
    _midiEngine.stopAll(tag: 'review-dispose');
    _midiEngine.clearContext(runId: _reviewRunId);
    _time.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_playing) return;
    
    // Use audio position as master clock - visuals MUST follow audio
    // If audio position is not available, freeze visuals
    if (_audioPositionSec == null) {
      // Don't advance visuals until audio starts
      return;
    }
    
    // Visual time is driven directly by audio position (master clock)
    final visualTimeMs = _audioPositionSec! * 1000.0;
    _time.value = _audioPositionSec!;
    
    // Update MIDI engine position for route change resumption
    if (_playing) {
      _midiEngine.updatePosition(_audioPositionSec!, runId: _reviewRunId);
    }
    
    // Debug logging (temporary) - log every 250-500ms
    if (kDebugMode) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastSyncLogTime >= 250) {
        _lastSyncLogTime = now;
        final audioTimeMs = _audioPositionSec! * 1000.0;
        final diffMs = visualTimeMs - audioTimeMs; // Should be 0
        debugPrint('[Review Sync] visualTimeMs=${visualTimeMs.toStringAsFixed(1)}, '
            'audioTimeMs=${audioTimeMs.toStringAsFixed(1)}, diffMs=${diffMs.toStringAsFixed(1)}');
        
        // Assert sync after first second
        if (_time.value > 1.0 && diffMs.abs() > 50) {
          debugPrint('[Review Sync WARNING] Desync detected: ${diffMs.toStringAsFixed(1)}ms');
        }
      }
    }
    
    if (_audioPositionSec! >= _durationSec) {
      _stop();
    }
  }

  Future<void> _start() async {
    if (_playing || !_preloadComplete) return;
    
    // Increment runId to cancel any in-flight operations
    _reviewRunId++;
    final currentRunId = _reviewRunId;
    
    final tapTime = DateTime.now().millisecondsSinceEpoch;
    final startOffsetSec = widget.startTimeSec;
    
    DebugLog.event(
      LogCat.replay,
      'replay_playback_start',
      runId: currentRunId,
      fields: {
        'tapTime': tapTime,
        'startOffsetSec': startOffsetSec,
        'notesCount': _notes.length,
        'durationSec': _durationSec,
      },
    );
    
    // Set visual time to start offset immediately (before audio starts)
    _time.value = startOffsetSec;
    
    _playing = true;
    _audioPositionSec = startOffsetSec; // Initialize to start offset
    _audioStarted = false;
    
    // Reset clock - visuals will be driven directly by audio position
    _clock.setLatencyCompensationMs(0);
    _clock.start(offsetSec: startOffsetSec, freezeUntilAudio: true);
    
    // Start ticker - it will update visuals from audio position
    _ticker?.start();
    
    // Ensure iOS audio session is configured for MIDI playback (especially with headphones)
    // This must be called BEFORE starting audio/MIDI playback
    await AudioSessionService.applyReviewSession(tag: 'review_start');
    
    // Start audio playback immediately (everything is preloaded)
    // Audio will be sought to startOffsetSec in _playAudio()
    // Capture exact playback start moment AFTER seek completes (this is the master clock anchor)
    await _playAudio();
    
    // Capture playback start epoch AFTER audio has been sought and started
    // This ensures MIDI notes use the same timeline anchor as recorded audio
    _playbackStartEpoch = DateTime.now();
    final playbackStartTime = _playbackStartEpoch!.millisecondsSinceEpoch;
    
    // Apply sync compensation if enabled (debug only)
    int? compensationMs;
    if (kDebugMode && kEnableSyncCompensation && _syncOffsetMs != null) {
      // If offsetMs > 0 (recorded audio is late), delay MIDI by offsetMs
      // This shifts MIDI scheduling to align with recorded audio
      compensationMs = _syncOffsetMs! > 0 ? _syncOffsetMs : 0;
      if (compensationMs != null && compensationMs > 0) {
        debugPrint('[Review Start] Applying sync compensation: ${compensationMs}ms delay to MIDI playback');
      }
    }
    
    if (kDebugMode) {
      debugPrint('[Review Start] playbackStartEpoch=$playbackStartTime (captured after seek), '
          'startOffsetSec=$startOffsetSec, LEAD_IN_MS=${ExerciseConstants.leadInMs}, '
          'syncOffsetMs=${_syncOffsetMs ?? "none"}, compensationMs=${compensationMs ?? "none"}');
    }
    
    // Check runId after async call
    if (!mounted || currentRunId != _reviewRunId) return;
    
    // Now start MIDI playback using audio-position-based scheduling
    // This ensures MIDI notes are synchronized with recorded audio by using the same clock
    await _playReference(useSecondaryPlayer: false, runId: currentRunId);
    
    // Check runId after async call
    if (!mounted || currentRunId != _reviewRunId) return;
    
    // For MIDI-only playback (no recorded audio), use a timer to drive visuals
    // MIDI notes are already scheduled with timers, so we just need to update visuals
    if (_recordedAudioPath == null && _midiOnlyTimer == null) {
      _midiOnlyStartTime = DateTime.now().millisecondsSinceEpoch;
      final startOffsetSec = widget.startTimeSec;
      _midiOnlyTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
        if (!_playing || _reviewRunId != currentRunId) {
          timer.cancel();
          _midiOnlyTimer = null;
          return;
        }
        
        // Calculate elapsed time since MIDI playback started
        final elapsedMs = DateTime.now().millisecondsSinceEpoch - (_midiOnlyStartTime ?? 0);
        final newPositionSec = (elapsedMs / 1000.0) + startOffsetSec;
        
        _audioPositionSec = newPositionSec;
        _time.value = newPositionSec;
      });
      
      if (kDebugMode) {
        debugPrint('[Review] Started MIDI-only timer for visual updates');
      }
    }
    
    final midiEngineStartTime = DateTime.now().millisecondsSinceEpoch;
    if (kDebugMode) {
      debugPrint('[Review Start] midiEngineStartTime=$midiEngineStartTime, '
          'latency=${midiEngineStartTime - playbackStartTime}ms');
      if (_notes.isNotEmpty) {
        // Find first note that's >= startOffsetSec
        final relevantNotes = _notes.where((n) => n.startSec >= startOffsetSec).toList();
        if (relevantNotes.isNotEmpty) {
          final firstNoteStartMs = relevantNotes.first.startSec * 1000.0;
          debugPrint('[Review Start] firstMidiNoteAfterOffset=${firstNoteStartMs}ms (offset=$startOffsetSec)');
        }
      }
    }
    
    if (mounted) setState(() {});
  }

  Future<void> _stop() async {
    if (!_playing) return;
    _playing = false;
    _ticker?.stop();
    _clock.pause();
    // Stop audio immediately - this will stop audio position updates
    await _synth.stop();
    await _midiEngine.stopAll(tag: 'review-stop');
    _midiEngine.clearContext(runId: _reviewRunId);
    await _audioPosSub?.cancel();
    _audioPosSub = null;
    await _audioCompleteSub?.cancel();
    _audioCompleteSub = null;
    _audioPositionSec = null;
    _audioStarted = false;
    if (mounted) setState(() {});
  }
  
  /// Called when primary recording playback completes
  Future<void> _onPlaybackComplete() async {
    if (kDebugMode) {
      debugPrint('[Review] Primary recording playback completed');
    }
    // Stop both MIDI and recorded audio
    await _stop();
    // Navigate back to previous screen
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _playAudio() async {
    final currentRunId = _reviewRunId;
    
    // Ensure iOS audio session is configured before starting playback
    // This is especially important for MIDI playback with headphones
    await AudioSessionService.applyReviewSession(tag: 'play_audio');
    
    // Seek to the start time before playing (if startTimeSec > 0)
    final startOffsetSec = widget.startTimeSec;
    
    if (kDebugMode) {
      debugPrint('[Review] startOffsetSec=$startOffsetSec');
    }
    
    final hasRecordedAudio = _recordedAudioPath != null && _recordedAudioPath!.isNotEmpty;
    final willPlayRecording = hasRecordedAudio;
    
    // Always play reference notes (MIDI guide tones via ReferenceMidiSynth)
    // If recorded audio exists, play it simultaneously on primary player
    if (hasRecordedAudio && willPlayRecording) {
      // Start recorded audio first, then MIDI will be started from _start() after seek completes
      await _synth.playFile(_recordedAudioPath!); // Start recorded audio on primary
      
      // Check runId after async call
      if (!mounted || currentRunId != _reviewRunId) return;
      
      // Seek primary player (recorded audio) to the start offset
      if (startOffsetSec > 0) {
        final seekPos = Duration(milliseconds: (startOffsetSec * 1000).round());
        
        // Log seek actions
        DebugLog.event(
          LogCat.seek,
          'segment_seek_recording',
          runId: currentRunId,
          fields: {
            'targetSec': startOffsetSec,
            'seekPosMs': seekPos.inMilliseconds,
            'willPlayRecording': willPlayRecording,
            'which': 'primary',
          },
        );
        
        // Seek primary player (recorded audio) - non-blocking with timeout
        final seekOk = await _synth.seek(seekPos, runId: currentRunId, timeout: const Duration(seconds: 2));
        if (!mounted || currentRunId != _reviewRunId) return;
        
        if (!seekOk) {
          DebugLog.event(
            LogCat.seek,
            'segment_seek_primary_timeout',
            runId: currentRunId,
            fields: {
              'targetSec': startOffsetSec,
              'warning': 'Primary seek timed out, continuing playback',
            },
          );
        }
        
        // Log after seek
        DebugLog.event(
          LogCat.seek,
          'segment_seek_complete',
          runId: currentRunId,
          fields: {
            'targetSec': startOffsetSec,
            'result': 'sought',
          },
        );
      }
    } else if (!willPlayRecording) {
      // No recorded audio - MIDI-only playback
      // Skip recording seek if we're not playing recording
      if (startOffsetSec > 0) {
        DebugLog.event(
          LogCat.seek,
          'skip_recording_seek',
          runId: currentRunId,
          fields: {
            'targetSec': startOffsetSec,
            'reason': 'willPlayRecording=false',
          },
        );
      }
      
      // Debug: log when audio actually starts
      if (kDebugMode) {
        final t0AudioStart = DateTime.now().millisecondsSinceEpoch;
        debugPrint('[Review Start] t0_audioStart=$t0AudioStart (MIDI-only playback, no recorded audio)');
      }
      
      // For MIDI-only playback, use a timer-based clock since there's no audio player
      await _audioPosSub?.cancel();
      await _playerStateSub?.cancel();
      _positionWatchdog?.cancel();
      _lastPositionUpdateMs = null;
      _audioPositionSec = startOffsetSec; // Initialize to start offset
      _audioStarted = true;
      
      // Timer will be started AFTER _playReference() initializes the MIDI sequence
      // (see _start() method after _playReference() completes)
      
      // Watchdog: if position hasn't updated in 500ms, poll manually
      _positionWatchdog = Timer.periodic(const Duration(milliseconds: 500), (timer) {
        if (!_playing) {
          timer.cancel();
          return;
        }
        
        final now = DateTime.now().millisecondsSinceEpoch;
        if (_lastPositionUpdateMs != null && (now - _lastPositionUpdateMs!) > 1000) {
          // Position stream appears stuck, poll manually
          _synth.getCurrentPosition().then((pos) {
            if (pos != null && _playing) {
              final newPositionSec = (pos.inMilliseconds / 1000.0) + startOffsetSec;
              if (_audioPositionSec == null || (newPositionSec - _audioPositionSec!).abs() > 0.01) {
                DebugLog.event(
                  LogCat.audio,
                  'audio_position_polled',
                  runId: _reviewRunId,
                  fields: {
                    'oldPosSec': _audioPositionSec,
                    'newPosSec': newPositionSec,
                    'posMs': pos.inMilliseconds,
                    'streamStuck': true,
                  },
                );
                _audioPositionSec = newPositionSec;
                _lastPositionUpdateMs = now;
              }
            }
          });
        }
      });
      
      // Listen for primary recording completion
      await _audioCompleteSub?.cancel();
      _audioCompleteSub = _synth.onComplete.listen((_) {
        _onPlaybackComplete();
      });
    } else {
      // No recorded audio, just play reference notes
      await _playReference();
      
      // Seek to the start offset
      if (startOffsetSec > 0) {
        final seekPos = Duration(milliseconds: (startOffsetSec * 1000).round());
        await _synth.seek(seekPos);
        if (kDebugMode) {
          debugPrint('[Review] audioSeeked=true at ${startOffsetSec.toStringAsFixed(2)}s');
        }
      }
    }
    
    if (kDebugMode) {
      debugPrint('[Review] playbackStartedAt=${startOffsetSec.toStringAsFixed(2)}s');
    }
  }

  Future<void> _playReference({bool useSecondaryPlayer = false, int? runId}) async {
    final currentRunId = runId ?? _reviewRunId;
    
    if (_notes.isEmpty) return;
    if (!mounted || currentRunId != _reviewRunId) return;
    
    // Use ReferenceMidiSynth for review playback (same as exercise) to ensure identical audio pipeline
    // This ensures both exercise and review use the same SoundFont, program, bank, channel, etc.
    final reviewConfig = MidiPlaybackConfig.review();
    
    // Filter and adjust notes for segment playback
    // If startTimeSec > 0, we're playing a segment - filter notes and adjust their timing
    final startOffsetSec = widget.startTimeSec;
    var notesToPlay = _filterAndAdjustNotesForSegment(_notes, startOffsetSec);
    
    if (notesToPlay.isEmpty) {
      if (kDebugMode) {
        debugPrint('[Review] No notes to play after filtering for segment (startOffsetSec=$startOffsetSec)');
      }
      return;
    }
    
    // Calculate the total offset to apply (diagnostic offset + manual offset)
    // Only apply if compensation toggle is enabled
    // Note: We apply offset via offsetMs parameter in playSequence(), not by modifying note times
    int totalOffsetMs = 0;
    if (_compensationEnabled) {
      final diagnosticOffset = (kDebugMode && kEnableSyncCompensation && _syncOffsetMs != null) ? _syncOffsetMs! : 0;
      totalOffsetMs = diagnosticOffset + _manualOffsetMs;
      if (kDebugMode && totalOffsetMs != 0) {
        debugPrint('[Review] Compensation enabled: totalOffsetMs=$totalOffsetMs (${diagnosticOffset}ms diagnostic + ${_manualOffsetMs}ms manual)');
      }
    } else if (kDebugMode) {
      debugPrint('[Review] Compensation disabled - using raw note timing');
    }
    
    // Log first note for review playback (for octave tripwire comparison)
    if (notesToPlay.isNotEmpty) {
      final firstNote = notesToPlay.first;
      final reviewMidi = firstNote.midi.round();
      final noteName = PitchMath.midiToName(reviewMidi);
      final hz = 440.0 * math.pow(2.0, (reviewMidi - 69) / 12.0);
      final difficulty = widget.lastTake.pitchDifficulty ?? 'unknown';
      debugPrint(
          '[OctaveTripwire] REVIEW playback: '
          'exerciseId=${widget.exercise.id}, difficulty=$difficulty, '
          'firstNoteMidi=$reviewMidi ($noteName), hz=${hz.toStringAsFixed(1)}, '
          'noteCount=${notesToPlay.length} (filtered from ${_notes.length}, startOffsetSec=$startOffsetSec)');
    }
    
    // Use timer-based scheduling with manual offset compensation
    // This ensures MIDI notes are delayed by the sync offset to align with recorded audio bleed
    if (kDebugMode) {
      debugPrint('[Review] MIDI playback (timer-based with offset): startOffsetSec=$startOffsetSec, '
          'notesCount=${notesToPlay.length}, firstNoteStartSec=${notesToPlay.first.startSec.toStringAsFixed(2)}, '
          'syncOffsetMs=${_syncOffsetMs ?? "none"}, manualOffsetMs=$_manualOffsetMs, compensationEnabled=$_compensationEnabled, totalOffsetMs=$totalOffsetMs');
    }
    
    // Start MIDI playback using timer-based scheduling with offset compensation
    // The offset will be applied when scheduling each note
    await _midiEngine.playSequence(
      notes: notesToPlay,
      leadInSec: 0.0, // Notes already include lead-in in their startSec
      runId: currentRunId,
      startEpochMs: _playbackStartEpoch?.millisecondsSinceEpoch,
      config: reviewConfig,
      offsetMs: totalOffsetMs, // Apply sync offset to delay MIDI notes
      mode: 'review',
    );
    
    if (kDebugMode) {
      debugPrint('[Review] MIDI sequence scheduled with timer-based playback, offset=${totalOffsetMs}ms');
    }
    
    // Set up position listener for visuals (recorded audio drives visual timeline)
    if (!useSecondaryPlayer) {
      await _audioPosSub?.cancel();
      _audioPosSub = _synth.onPositionChanged.listen((pos) {
        if (!_audioStarted && pos > Duration.zero) {
          _audioStarted = true;
          if (kDebugMode) {
            debugPrint('[Review Start] Audio position stream started, first pos=${pos.inMilliseconds}ms');
          }
        }
        
        // Update audio position for visuals (visuals follow recorded audio)
        final newPositionSec = (pos.inMilliseconds / 1000.0) + startOffsetSec;
        _audioPositionSec = newPositionSec;
        
        // Visual time is driven directly by audio position (master clock)
        // MIDI notes are scheduled independently with offset compensation
      });
    
    // Listen for reference notes completion (when no recorded audio)
    await _audioCompleteSub?.cancel();
    _audioCompleteSub = _synth.onComplete.listen((_) {
      _onPlaybackComplete();
    });
    }
  }

  double _computeDuration(List<ReferenceNote> notes) {
    final specDuration =
        notes.isEmpty ? 0.0 : notes.map((n) => n.endSec).fold(0.0, math.max);
    return math.max(widget.lastTake.durationSec, specDuration) +
        AudioSynthService.tailSeconds;
  }


  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    final noteMidis = _notes.map((n) => n.midi.toDouble()).toList();
    final contourMidis = widget.lastTake.frames
        .map((f) => f.midi ?? (f.hz != null ? PitchMath.hzToMidi(f.hz!) : null))
        .whereType<double>()
        .toList();
    
    // For Sirens, use visual path for MIDI range (more accurate)
    final minMidi = widget.exercise.id == 'sirens' && _sirenVisualPath != null && _sirenVisualPath!.points.isNotEmpty
        ? (_sirenVisualPath!.points.map((p) => p.midiFloat).reduce((a, b) => a < b ? a : b).floor() - 3)
        : (noteMidis.isNotEmpty || contourMidis.isNotEmpty
            ? ([...noteMidis, ...contourMidis].reduce(math.min).floor() - 3)
            : 48);
    final maxMidi = widget.exercise.id == 'sirens' && _sirenVisualPath != null && _sirenVisualPath!.points.isNotEmpty
        ? (_sirenVisualPath!.points.map((p) => p.midiFloat).reduce((a, b) => a > b ? a : b).ceil() + 3)
        : (noteMidis.isNotEmpty || contourMidis.isNotEmpty
            ? ([...noteMidis, ...contourMidis].reduce(math.max).ceil() + 3)
            : 72);
    assert(() {
      debugPrint('[Review] exerciseId: ${widget.lastTake.exerciseId}');
      if (noteMidis.isNotEmpty) {
        debugPrint('[Review] note midi range: '
            '${noteMidis.reduce(math.min)}..${noteMidis.reduce(math.max)}');
      }
      if (contourMidis.isNotEmpty) {
        debugPrint('[Review] contour midi range: '
            '${contourMidis.reduce(math.min)}..${contourMidis.reduce(math.max)}');
      }
      debugPrint('[Review] viewport midi: $minMidi..$maxMidi');
      return true;
    }());
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Review last take'),
        actions: [
          // Manual offset adjustment controls (debug only)
          if (kDebugMode)
            _OffsetAdjustmentControls(
              currentOffsetMs: _manualOffsetMs,
              diagnosticOffsetMs: _syncOffsetMs,
              compensationEnabled: _compensationEnabled,
              onOffsetChanged: (newOffsetMs) {
                setState(() {
                  _manualOffsetMs = newOffsetMs;
                });
                // Restart playback if currently playing to apply new offset
                if (_playing) {
                  _stop();
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (mounted && _preloadComplete) {
                      _start();
                    }
                  });
                }
              },
              onCompensationToggled: (enabled) {
                setState(() {
                  _compensationEnabled = enabled;
                });
                // Restart playback if currently playing to apply toggle change
                if (_playing) {
                  _stop();
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (mounted && _preloadComplete) {
                      _start();
                    }
                  });
                }
              },
            ),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _playing
                ? _stop
                : (_preloadComplete ? _start : () {}), // Disabled until preload complete
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (kDebugMode && !_loggedGraphInfo) {
                  debugPrint(
                    'REVIEW GRAPH: height=${constraints.maxHeight} '
                    'topPad=0.0 bottomPad=0.0 '
                    'viewportMinMidi=$minMidi viewportMaxMidi=$maxMidi',
                  );
                  _loggedGraphInfo = true;
                }
                return Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: PitchHighwayPainter(
                          notes: _notes,
                          pitchTail: widget.lastTake.frames,
                          time: _time,
                          pixelsPerSecond: _pixelsPerSecond,
                          playheadFraction: 0.45,
                          smoothingWindowSec: 0.12,
                          drawBackground: false,
                          showLivePitch: false,
                          showPlayheadLine: false,
                          midiMin: minMidi,
                          midiMax: maxMidi,
                          colors: colors,
                          debugLogMapping: true,
                          sirenPath: _sirenVisualPath, // Pass visual path for Sirens bell curve
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: PitchContourPainter(
                          frames: widget.lastTake.frames,
                          time: _time,
                          pixelsPerSecond: _pixelsPerSecond,
                          playheadFraction: 0.45,
                          midiMin: minMidi,
                          midiMax: maxMidi,
                          glowColor: colors.goldAccent,
                          coreColor: colors.goldAccent,
                          debugLogMapping: true,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _PlayheadPainter(
                          playheadFraction: 0.45,
                          lineColor: colors.blueAccent.withOpacity(0.7),
                          shadowColor: Colors.black.withOpacity(0.3),
                        ),
                      ),
                    ),
                    if (kDebugMode && _notes.isNotEmpty)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _DebugYLinePainter(
                            midi: _notes.first.midi.toDouble(),
                            midiMin: minMidi,
                            midiMax: maxMidi,
                            color: Colors.red.withOpacity(0.5),
                          ),
                        ),
                      ),
                    // Loading overlay
                    if (!_preloadComplete)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withOpacity(0.7),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                Text(
                                  'Loading...',
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayheadPainter extends CustomPainter {
  final double playheadFraction;
  final Color lineColor;
  final Color shadowColor;

  const _PlayheadPainter({
    required this.playheadFraction,
    required this.lineColor,
    required this.shadowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * playheadFraction;
    final shadowPaint = Paint()
      ..color = shadowColor
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(x + 0.5, 0), Offset(x + 0.5, size.height), shadowPaint);
    final playheadPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), playheadPaint);
  }

  @override
  bool shouldRepaint(covariant _PlayheadPainter oldDelegate) {
    return oldDelegate.playheadFraction != playheadFraction;
  }
}

class _DebugYLinePainter extends CustomPainter {
  final double midi;
  final int midiMin;
  final int midiMax;
  final Color color;

  _DebugYLinePainter({
    required this.midi,
    required this.midiMin,
    required this.midiMax,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final y = PitchMath.midiToY(
      midi: midi,
      height: size.height,
      midiMin: midiMin,
      midiMax: midiMax,
    );
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }

  @override
  bool shouldRepaint(covariant _DebugYLinePainter oldDelegate) {
    return oldDelegate.midi != midi ||
        oldDelegate.midiMin != midiMin ||
        oldDelegate.midiMax != midiMax ||
        oldDelegate.color != color;
  }
}

/// Manual offset adjustment controls widget (debug only)
/// Allows fine-tuning MIDI playback timing relative to recorded audio
class _OffsetAdjustmentControls extends StatelessWidget {
  final int currentOffsetMs;
  final int? diagnosticOffsetMs;
  final bool compensationEnabled;
  final ValueChanged<int> onOffsetChanged;
  final ValueChanged<bool> onCompensationToggled;

  const _OffsetAdjustmentControls({
    required this.currentOffsetMs,
    required this.diagnosticOffsetMs,
    required this.compensationEnabled,
    required this.onOffsetChanged,
    required this.onCompensationToggled,
  });

  void _adjustOffset(int deltaMs) {
    onOffsetChanged(currentOffsetMs + deltaMs);
  }

  @override
  Widget build(BuildContext context) {
    final totalOffsetMs = (diagnosticOffsetMs ?? 0) + currentOffsetMs;
    final isPositive = totalOffsetMs > 0;
    final isNegative = totalOffsetMs < 0;
    
    return PopupMenuButton<String>(
      tooltip: 'Adjust MIDI offset (${totalOffsetMs > 0 ? "+" : ""}$totalOffsetMs ms)',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPositive ? Icons.arrow_forward : (isNegative ? Icons.arrow_back : Icons.sync),
              color: isPositive 
                  ? Colors.orange 
                  : (isNegative ? Colors.blue : Colors.grey),
              size: 20,
            ),
            const SizedBox(width: 4),
            Text(
              '${totalOffsetMs > 0 ? "+" : ""}$totalOffsetMs',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isPositive 
                    ? Colors.orange 
                    : (isNegative ? Colors.blue : Colors.grey),
              ),
            ),
          ],
        ),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: StatefulBuilder(
            builder: (context, setMenuState) {
              // Use local state that syncs with parent state
              bool localEnabled = compensationEnabled;
              
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MIDI Offset',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Enable Compensation',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                      Switch(
                        value: localEnabled,
                        onChanged: (value) {
                          // Update local state immediately for visual feedback
                          setMenuState(() {
                            localEnabled = value;
                          });
                          // Update parent state
                          onCompensationToggled(value);
                        },
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    localEnabled 
                        ? 'Total: ${totalOffsetMs > 0 ? "+" : ""}$totalOffsetMs ms'
                        : 'Compensation OFF (using audio-position sync)',
                    style: TextStyle(
                      fontSize: 12, 
                      color: localEnabled ? Colors.grey[700] : Colors.grey[500],
                      fontStyle: localEnabled ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                  if (localEnabled && diagnosticOffsetMs != null)
                    Text(
                      'Diagnostic: ${diagnosticOffsetMs! > 0 ? "+" : ""}${diagnosticOffsetMs!} ms',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  if (localEnabled)
                    Text(
                      'Manual: ${currentOffsetMs > 0 ? "+" : ""}$currentOffsetMs ms',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                ],
              );
            },
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Delay MIDI (+50ms)'),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                onPressed: () => _adjustOffset(50),
                tooltip: 'Delay MIDI by 50ms',
              ),
            ],
          ),
        ),
        PopupMenuItem(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Delay MIDI (+10ms)'),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                onPressed: () => _adjustOffset(10),
                tooltip: 'Delay MIDI by 10ms',
              ),
            ],
          ),
        ),
        PopupMenuItem(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Advance MIDI (-10ms)'),
              IconButton(
                icon: const Icon(Icons.remove, size: 18),
                onPressed: () => _adjustOffset(-10),
                tooltip: 'Advance MIDI by 10ms',
              ),
            ],
          ),
        ),
        PopupMenuItem(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Advance MIDI (-50ms)'),
              IconButton(
                icon: const Icon(Icons.remove, size: 18),
                onPressed: () => _adjustOffset(-50),
                tooltip: 'Advance MIDI by 50ms',
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Reset to diagnostic'),
              TextButton(
                onPressed: () => onOffsetChanged(0),
                child: const Text('Reset'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
