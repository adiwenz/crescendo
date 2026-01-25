import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../models/last_take.dart';
import '../../models/pitch_highway_difficulty.dart';
import '../../models/reference_note.dart';
import '../../models/vocal_exercise.dart';
import '../../models/siren_path.dart';
import '../../models/pitch_frame.dart';
import '../../services/audio_synth_service.dart';
import '../../services/review_audio_bounce_service.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../audio/midi_playback_config.dart';
import '../../services/transposed_exercise_builder.dart';
import '../../services/vocal_range_service.dart';
import '../../utils/pitch_highway_tempo.dart';
import '../../utils/pitch_math.dart';
import '../../utils/performance_clock.dart';
import '../../utils/audio_constants.dart';
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
  // No MIDI engine needed - using bounced audio for review playback
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
  static const double _leadInSec = AudioConstants.leadInSec;
  bool _loggedGraphInfo = false;
  late final double _pixelsPerSecond;
  
  // Preload state
  bool _preloadComplete = false;
  bool _preloading = false;
  String? _referenceAudioPath;
  String? _recordedAudioPath;
  String? _mixedAudioPath; // Bounced mixed WAV (mic + reference)
  bool _showReference = true; // Toggle: true = mixed (with reference), false = mic only
  final ReviewAudioBounceService _bounceService = ReviewAudioBounceService();
  DateTime? _playbackStartEpoch; // Exact moment playback truly starts
  int _lastSyncLogTime = 0;
  int _reviewRunId = 0; // Run ID for review MIDI playback
  int? _midiOnlyStartTime; // Start time for MIDI-only timer (set after MIDI sequence is initialized)
  
  // Sync compensation (debug only)
  static const bool kEnableSyncCompensation = true; // Set to false to disable compensation
  int? _syncOffsetMs; // Cached sync offset from diagnostic
  int _manualOffsetMs = 0; // Manual offset adjustment (can be positive or negative)
  bool _compensationEnabled = true; // Toggle to enable/disable compensation (default: enabled)

  // Rebase state
  List<PitchFrame> _rebasedFrames = const [];
  double _sliceStartSec = 0.0;
  double _renderStartSec = 0.0; // Anchor for visual 0.0
  double _micOffsetSec = 0.0; // Where the mic starts in the replayed file

  @override
  void initState() {
    super.initState();
    
    // Initialize MIDI engine (sets up route change listeners automatically)
    // No MIDI engine initialization needed - using bounced audio
    
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

    // --- REBASE LOGIC ---
    // Use the explicit recorder start time from the take
    _sliceStartSec = widget.lastTake.recorderStartSec ?? 0.0;

    // Determine the anchor for all visuals and audio (0.0 in the rebased domain)
    // We prioritize providing the 2s lead-in before the recording start.
    // If a specific startTimeSec was requested (e.g. 26s for a 28s segment), we use it.
    _renderStartSec = widget.startTimeSec;
    if (_renderStartSec > _sliceStartSec) {
      // If requested start is AFTER recording, we still rebase to show context if possible
      // but typical case is segment_start - 2s.
    }
    
    _micOffsetSec = math.max(0.0, _sliceStartSec - _renderStartSec);

    // Shift frames to be relative to renderStartSec
    // widget.lastTake.frames are natively 0-based relative to recorder start
    _rebasedFrames = widget.lastTake.frames.map<PitchFrame>((f) => PitchFrame(
      time: f.time + _micOffsetSec,
      hz: f.hz,
      midi: f.midi,
      voicedProb: f.voicedProb,
      rms: f.rms,
    )).toList();
    
    _time.value = 0.0; // Replayed domain always starts at 0.0
    // ----------------------

    // Step 2: Check recorded audio path
    _recordedAudioPath = widget.lastTake.audioPath;
    
    // Load sync offset for compensation (debug only)
    if (kDebugMode && kEnableSyncCompensation) {
      _loadSyncOffset();
    }
    
    // Log replay start (now with assigned paths)
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
    
    // Step 3: Render and mix audio (bounce MIDI to WAV, then mix with recorded audio)
    // This eliminates timer-based real-time MIDI scheduling for route-change resilience
    if (_notes.isNotEmpty && _recordedAudioPath != null) {
      await _bounceAndMixAudio(difficulty);
    } else if (_notes.isNotEmpty) {
      // No recorded audio, just render reference WAV
      await _bounceReferenceAudio(difficulty);
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
  
  /// Bounce reference audio and mix with recorded audio
  Future<void> _bounceAndMixAudio(PitchHighwayDifficulty difficulty) async {
    try {
      // Generate cache key
      final takeFileName = p.basename(_recordedAudioPath ?? '');
      final reviewConfig = MidiPlaybackConfig.review();
      
      if (kDebugMode) {
        debugPrint('[Review Bounce] Notes count: ${_notes.length}, duration=${_durationSec.toStringAsFixed(2)}s, renderStart=${_renderStartSec.toStringAsFixed(2)}s, micOffset=${_micOffsetSec.toStringAsFixed(2)}s');
      }
      
      final cacheKey = ReviewAudioBounceService.generateCacheKey(
        takeFileName: takeFileName,
        exerciseId: widget.exercise.id,
        transposeSemitones: 0, // Review doesn't transpose
        soundFontName: reviewConfig.soundFontName,
        program: reviewConfig.program,
        sampleRate: ReviewAudioBounceService.defaultSampleRate,
        renderStartSec: _renderStartSec,
      );
      
      // Check cache first
      final cachedMixed = await ReviewAudioBounceService.getCachedMixedWav(cacheKey);
      if (cachedMixed != null) {
        _mixedAudioPath = cachedMixed.path;
        if (kDebugMode) {
          debugPrint('[Review Bounce] Using cached mixed WAV: ${_mixedAudioPath}');
        }
        return;
      }
      
      if (kDebugMode) {
        debugPrint('[Review Bounce] Cache miss, rendering and mixing audio...');
      }
      
      // Render reference WAV
      final referenceWav = await _bounceService.renderReferenceWav(
        notes: _notes,
        durationSec: _durationSec,
        sampleRate: ReviewAudioBounceService.defaultSampleRate,
        soundFontAssetPath: reviewConfig.soundFontAssetPath,
        program: reviewConfig.program,
      );
      
      // Mix with recorded audio
      final micWav = File(_recordedAudioPath!);
      final mixedWav = await _bounceService.mixWavs(
        micWav: micWav,
        referenceWav: referenceWav,
        micGain: 1.0,
        refGain: 1.0,
        micOffsetSec: _micOffsetSec,
        duckMicWhileRef: false,
      );
      
      // Save to cache
      final cacheDir = await ReviewAudioBounceService.getCacheDirectory();
      final cachedFile = File(p.join(cacheDir.path, '${cacheKey}_mixed.wav'));
      await mixedWav.copy(cachedFile.path);
      
      _mixedAudioPath = cachedFile.path;
      
      if (kDebugMode) {
        debugPrint('[Review Bounce] Mixed WAV created and cached: ${_mixedAudioPath}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Review Bounce] Error bouncing/mixing audio: $e');
      }
      // Fallback: continue without mixed audio (will use real-time MIDI)
    }
  }
  
  /// Bounce reference audio only (no recorded audio)
  Future<void> _bounceReferenceAudio(PitchHighwayDifficulty difficulty) async {
    try {
      final reviewConfig = MidiPlaybackConfig.review();
      
      // Render reference WAV
      final referenceWav = await _bounceService.renderReferenceWav(
        notes: _notes,
        durationSec: _durationSec,
        sampleRate: ReviewAudioBounceService.defaultSampleRate,
        soundFontAssetPath: reviewConfig.soundFontAssetPath,
        program: reviewConfig.program,
      );
      
      _referenceAudioPath = referenceWav.path;
      
      if (kDebugMode) {
        debugPrint('[Review Bounce] Reference WAV rendered: ${_referenceAudioPath}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Review Bounce] Error bouncing reference audio: $e');
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
        // --- REBASE NOTES ---
      final rebasedNotes = notes.map<ReferenceNote>((n) => ReferenceNote(
        midi: n.midi,
        startSec: math.max(0, n.startSec - _renderStartSec),
        endSec: math.max(0, n.endSec - _renderStartSec),
        lyric: n.lyric,
        isGlideStart: n.isGlideStart,
        isGlideEnd: n.isGlideEnd,
      )).where((n) => n.endSec > 0).toList();

      final rebasedSirenPath = sirenPath != null ? SirenPath(
        points: sirenPath.points.map<SirenPoint>((p) => SirenPoint(
          tSec: math.max(0, p.tSec - _renderStartSec),
          midiFloat: p.midiFloat,
        )).where((p) => p.tSec >= 0).toList()
      ) : null;
      // --------------------

      if (!mounted) return;
      setState(() {
        _notes = rebasedNotes;
        _sirenVisualPath = rebasedSirenPath;
        _durationSec = widget.lastTake.durationSec + _micOffsetSec;
      });
      
      // Try to auto-start if preload is already complete
      // Otherwise, preload completion will trigger auto-start
      if (rebasedNotes.isNotEmpty && !_playing && _preloadComplete) {
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
    // No MIDI engine cleanup needed - using bounced audio, not real-time MIDI
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
    _time.value = _audioPositionSec!;
    
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
    // Current rendered file already includes requested lead-in and starts at _renderStartSec.
    // Visual domain 0.0 = audio file 0.0 = Exercise time _renderStartSec.
    final startOffsetSec = 0.0;
    
    DebugLog.event(
      LogCat.replay,
      'replay_playback_start',
      runId: currentRunId,
      fields: {
        'tapTime': tapTime,
        'renderStartSec': _renderStartSec,
        'micOffsetSec': _micOffsetSec,
        'durationSec': _durationSec,
      },
    );
    
    _time.value = 0.0;
    
    _playing = true;
    _audioPositionSec = 0.0;
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
          'startOffsetSec=$startOffsetSec, LEAD_IN_MS=${AudioConstants.leadInMs}, '
          'syncOffsetMs=${_syncOffsetMs ?? "none"}, compensationMs=${compensationMs ?? "none"}');
    }
    
    // Check runId after async call
    if (!mounted || currentRunId != _reviewRunId) return;
    
    // NO REAL-TIME MIDI: We use bounced/mixed WAV instead
    // This eliminates timer-based scheduling and route change issues
    if (kDebugMode) {
      debugPrint('[Review Start] Using bounced audio (no real-time MIDI): mixed=${_mixedAudioPath != null}, ref=${_referenceAudioPath != null}');
    }
    
    // For reference-only playback (no recorded audio), use a timer to drive visuals
    // if we don't have bounced reference WAV
    if (_recordedAudioPath == null && _referenceAudioPath == null && _midiOnlyTimer == null) {
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
    // No MIDI to stop - we use bounced WAV, not real-time MIDI
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
    
    // Use bounced/mixed WAV if available, otherwise fall back to recorded audio only
    String? audioToPlay;
    if (_showReference && _mixedAudioPath != null) {
      // Play mixed WAV (mic + reference)
      audioToPlay = _mixedAudioPath;
      if (kDebugMode) {
        debugPrint('[Review] SUCCESS: Playing MIXED WAV (piano + voice): ${audioToPlay}');
      }
    } else if (_showReference && _referenceAudioPath != null) {
      // Play reference-only WAV (no recorded audio)
      audioToPlay = _referenceAudioPath;
      if (kDebugMode) {
        debugPrint('[Review] INFO: Playing REFERENCE-ONLY WAV: ${audioToPlay}');
      }
    } else {
      // Play recorded audio only (reference toggle off or mixing failed)
      audioToPlay = _recordedAudioPath;
      if (kDebugMode) {
        if (_showReference) {
          debugPrint('[Review] WARNING: Mixing failed or mixed file missing. Falling back to MIC-ONLY: ${audioToPlay}');
        } else {
          debugPrint('[Review] INFO: Playing MIC-ONLY (reference toggled off): ${audioToPlay}');
        }
      }
    }
    
    if (audioToPlay != null) {
      // Play the bounced/mixed WAV or recorded audio
      // We play from the BEGINNING of this file as it's already pre-rendered for this review session.
      await _synth.playFile(audioToPlay);
      
      // Check runId after async call
      if (!mounted || currentRunId != _reviewRunId) return;
      
      // No internal seek needed - file starts at rebased 0.0
      
      // Set up position listener for visuals
      await _audioPosSub?.cancel();
      _audioPosSub = _synth.onPositionChanged.listen((pos) {
        if (!_audioStarted && pos > Duration.zero) {
          _audioStarted = true;
          if (kDebugMode) {
            debugPrint('[Review] Audio started, position stream active');
          }
        }
        _audioPositionSec = pos.inMilliseconds / 1000.0;
        _lastPositionUpdateMs = DateTime.now().millisecondsSinceEpoch;
      });
      
      // Set up completion listener
      await _audioCompleteSub?.cancel();
      _audioCompleteSub = _synth.onComplete.listen((_) {
        _onPlaybackComplete();
      });
    } else {
      // No audio file available - fallback to MIDI-only (shouldn't happen with bounced audio)
      if (kDebugMode) {
        debugPrint('[Review] WARNING: No audio file available, falling back to MIDI-only');
      }
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
      
      // Timer for visual updates (no audio file available)
      
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
    }
    
    if (kDebugMode) {
      debugPrint('[Review] playbackStartedAt=${startOffsetSec.toStringAsFixed(2)}s');
    }
  }

  // _playReference method removed - we use bounced WAV instead of real-time MIDI

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
          // Reference toggle button
          if (_mixedAudioPath != null || _referenceAudioPath != null)
            IconButton(
              icon: Icon(_showReference ? Icons.music_note : Icons.mic),
              tooltip: _showReference ? 'Show reference (mixed)' : 'Show mic only',
              onPressed: () {
                setState(() {
                  _showReference = !_showReference;
                });
                // Restart playback with new audio source
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
          // Force re-render button (debug only)
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Force re-render (clear cache)',
              onPressed: () async {
                // Clear cache and re-render
                final reviewConfig = MidiPlaybackConfig.review();
                final takeFileName = p.basename(_recordedAudioPath ?? '');
                final cacheKey = ReviewAudioBounceService.generateCacheKey(
                  takeFileName: takeFileName,
                  exerciseId: widget.exercise.id,
                  transposeSemitones: 0,
                  soundFontName: reviewConfig.soundFontName,
                  program: reviewConfig.program,
                  sampleRate: ReviewAudioBounceService.defaultSampleRate,
                );
                final cacheDir = await ReviewAudioBounceService.getCacheDirectory();
                final cachedFile = File(p.join(cacheDir.path, '${cacheKey}_mixed.wav'));
                if (await cachedFile.exists()) {
                  await cachedFile.delete();
                  if (kDebugMode) {
                    debugPrint('[Review] Cleared cached mixed WAV: ${cachedFile.path}');
                  }
                }
                _mixedAudioPath = null;
                _referenceAudioPath = null;
                // Re-bounce
                final difficulty = pitchHighwayDifficultyFromName(widget.lastTake.pitchDifficulty) ?? PitchHighwayDifficulty.medium;
                await _bounceAndMixAudio(difficulty);
                if (mounted) setState(() {});
              },
            ),
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
                          frames: _rebasedFrames,
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
