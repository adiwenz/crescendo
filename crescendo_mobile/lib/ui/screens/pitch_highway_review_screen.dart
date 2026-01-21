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
import '../../audio/reference_midi_synth.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../audio/midi_playback_config.dart';
import '../../services/transposed_exercise_builder.dart';
import '../../services/vocal_range_service.dart';
import '../../utils/pitch_highway_tempo.dart';
import '../../utils/pitch_math.dart';
import '../../utils/performance_clock.dart';
import '../../utils/exercise_constants.dart';
import '../../debug/debug_log.dart' show DebugLog, LogCat;
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
  final ReferenceMidiSynth _referenceMidiSynth = ReferenceMidiSynth();
  final VocalRangeService _vocalRangeService = VocalRangeService();
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  final PerformanceClock _clock = PerformanceClock();
  Ticker? _ticker;
  bool _playing = false;
  StreamSubscription<Duration>? _audioPosSub;
  StreamSubscription<void>? _audioCompleteSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  Timer? _positionWatchdog;
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

  @override
  void initState() {
    super.initState();
    
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
    
    // Step 2: Pre-render reference notes audio (for backward compatibility with WAV path)
    // NOTE: Review now uses ReferenceMidiSynth for real-time playback (same as exercise),
    // but we still render WAV as fallback or for mixing with recorded audio
    if (_notes.isNotEmpty) {
      _referenceAudioPath = await _synth.renderReferenceNotes(_notes);
      if (kDebugMode) {
        debugPrint('[Review Preload] Reference audio rendered (WAV fallback): ${_referenceAudioPath}');
        debugPrint('[Review Preload] Review will use ReferenceMidiSynth for real-time MIDI (same as exercise)');
      }
    }
    
    // Step 3: Check recorded audio
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
    
    // Step 4: Warm up audio engine (silent warmup)
    await _warmupAudioEngine();
    
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
  
  /// Warm up the audio engine to eliminate first-play latency
  Future<void> _warmupAudioEngine() async {
    try {
      // Render a very short silent audio clip to warm up the engine
      final warmupNotes = [
        ReferenceNote(startSec: 0, endSec: 0.05, midi: 60), // 50ms silent note
      ];
      final warmupPath = await _synth.renderReferenceNotes(warmupNotes);
      // Play it at very low volume (or we could just load it without playing)
      // Actually, just loading it should warm up the engine
      // We'll dispose of it immediately
      final warmupFile = File(warmupPath);
      if (await warmupFile.exists()) {
        // Just touch the file to ensure it's ready - the act of rendering already warmed up
        await warmupFile.delete(); // Clean up
      }
      if (kDebugMode) {
        debugPrint('[Review Preload] Audio engine warmed up');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Review Preload] Warmup error (non-fatal): $e');
      }
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
    
    _ticker?.dispose();
    _audioPosSub?.cancel();
    _audioCompleteSub?.cancel();
    _playerStateSub?.cancel();
    _positionWatchdog?.cancel();
    _synth.stop();
    _referenceMidiSynth.stop(); // Stop MIDI playback when navigating away
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
    
    // Capture exact playback start moment (this is the master clock anchor)
    _playbackStartEpoch = DateTime.now();
    final playbackStartTime = _playbackStartEpoch!.millisecondsSinceEpoch;
    
    if (kDebugMode) {
      debugPrint('[Review Start] playbackStartEpoch=$playbackStartTime, '
          'startOffsetSec=$startOffsetSec, LEAD_IN_MS=${ExerciseConstants.leadInMs}');
    }
    
    // Start audio playback immediately (everything is preloaded)
    // Audio will be sought to startOffsetSec in _playAudio()
    await _playAudio();
    
    // Check runId after async call
    if (!mounted || currentRunId != _reviewRunId) return;
    
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
    await _referenceMidiSynth.stop(); // Stop MIDI playback
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
      // Play both recorded audio and reference notes simultaneously
      // Reference notes via ReferenceMidiSynth (real-time MIDI), recorded audio on primary player
      await _playReference(useSecondaryPlayer: false, runId: currentRunId); // Start reference notes via MIDI
      
      // Check runId after async call
      if (!mounted || currentRunId != _reviewRunId) return;
      
      await _synth.playFile(_recordedAudioPath!); // Then start recorded audio on primary
      
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
      // No recorded audio, just play reference notes via MIDI
      await _playReference(useSecondaryPlayer: false, runId: currentRunId);
      
      // Check runId after async call
      if (!mounted || currentRunId != _reviewRunId) return;
      
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
        debugPrint('[Review Start] t0_audioStart=$t0AudioStart (recorded audio + reference notes playback began)');
      }
      
      // Use primary player's position (recorded audio) as master clock
      await _audioPosSub?.cancel();
      await _playerStateSub?.cancel();
      _positionWatchdog?.cancel();
      _lastPositionUpdateMs = null;
      
      // Also listen to player state changes to detect if playback stops
      _playerStateSub = _synth.onPlayerStateChanged.listen((state) {
        DebugLog.event(
          LogCat.audio,
          'player_state_changed',
          runId: _reviewRunId,
          fields: {
            'state': state.toString(),
            'isPlaying': state == PlayerState.playing,
          },
        );
        
        // If player stopped/paused, cancel watchdog
        if (state != PlayerState.playing) {
          _positionWatchdog?.cancel();
        }
      });
      
      _audioPosSub = _synth.onPositionChanged.listen((pos) {
        _lastPositionUpdateMs = DateTime.now().millisecondsSinceEpoch;
        
        if (!_audioStarted && pos > Duration.zero) {
          _audioStarted = true;
          DebugLog.event(
            LogCat.audio,
            'audio_position_first_update',
            runId: _reviewRunId,
            fields: {
              'posMs': pos.inMilliseconds,
              'startOffsetSec': startOffsetSec,
            },
          );
        }
        
        if (_audioStarted) {
          // Audio position is relative to audio file start
          // Add the start offset to get the actual timeline position
          final newPositionSec = (pos.inMilliseconds / 1000.0) + startOffsetSec;
          
          // Detect if position is stuck (not advancing)
          if (_audioPositionSec != null && (newPositionSec - _audioPositionSec!).abs() < 0.001) {
            DebugLog.log(
              LogCat.audio,
              'audio_position_stuck',
              key: 'position_stuck',
              throttleMs: 1000,
              runId: _reviewRunId,
              extraMap: {
                'posSec': newPositionSec,
                'posMs': pos.inMilliseconds,
              },
            );
          }
          
          _audioPositionSec = newPositionSec;
          
          // Visual time is driven directly by audio position (master clock)
          // This ensures perfect sync
        }
      });
      
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
    
    // Log first note for review playback (for octave tripwire comparison)
    if (_notes.isNotEmpty) {
      final firstNote = _notes.first;
      final reviewMidi = firstNote.midi.round();
      final noteName = PitchMath.midiToName(reviewMidi);
      final hz = 440.0 * math.pow(2.0, (reviewMidi - 69) / 12.0);
      final difficulty = widget.lastTake.pitchDifficulty ?? 'unknown';
      debugPrint(
          '[OctaveTripwire] REVIEW playback: '
          'exerciseId=${widget.exercise.id}, difficulty=$difficulty, '
          'firstNoteMidi=$reviewMidi ($noteName), hz=${hz.toStringAsFixed(1)}, '
          'noteCount=${_notes.length}');
    }
    
    // Use ReferenceMidiSynth for real-time MIDI playback (same as exercise)
    // This ensures identical audio pipeline: same SoundFont, same synth, same configuration
    final startEpochMs = DateTime.now().millisecondsSinceEpoch;
    
    await _referenceMidiSynth.playSequence(
      notes: _notes,
      leadInSec: 0.0, // Lead-in is already in note timestamps
      runId: currentRunId,
      startEpochMs: startEpochMs,
      config: reviewConfig,
    );
    
    // Debug: log when reference MIDI playback starts
    if (kDebugMode) {
      final t0AudioStart = DateTime.now().millisecondsSinceEpoch;
      debugPrint('[Review Start] t0_audioStart=$t0AudioStart (reference MIDI playback began, using ReferenceMidiSynth)');
    }
    
    // Only set up position listener if we're not already listening to recorded audio
    // (i.e., when useSecondaryPlayer is false, meaning we're playing reference only)
    if (!useSecondaryPlayer) {
    await _audioPosSub?.cancel();
    _audioPosSub = _synth.onPositionChanged.listen((pos) {
      if (!_audioStarted && pos > Duration.zero) {
        _audioStarted = true;
          // Debug: log when audio position first becomes available
          if (kDebugMode) {
            debugPrint('[Review Start] Audio position stream started, first pos=${pos.inMilliseconds}ms');
          }
      }
      if (_audioStarted) {
          // Audio position is relative to audio file start, which includes lead-in silence
          // Chart time also includes lead-in, so they should be in sync
        _audioPositionSec = pos.inMilliseconds / 1000.0;
          
          // Visual time is driven directly by audio position (master clock)
          // This ensures perfect sync
      }
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
