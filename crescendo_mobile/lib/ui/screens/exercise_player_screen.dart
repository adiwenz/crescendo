import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import '../../models/exercise_plan.dart';

import '../../models/pitch_frame.dart';
import '../../models/pitch_highway_difficulty.dart';
import '../../models/pitch_highway_spec.dart';
import '../../models/pitch_segment.dart';
import '../../models/reference_note.dart';
import '../../models/siren_path.dart';
import '../../models/vocal_exercise.dart';
import '../../models/last_take.dart';
import '../../models/exercise_level_progress.dart';
import '../../services/audio_synth_service.dart';
import '../../services/last_take_store.dart';
import '../../services/progress_service.dart';
import '../../services/recording_service.dart';
import '../../services/robust_note_scoring_service.dart';
import '../../services/exercise_level_progress_repository.dart';
import '../../services/transposed_exercise_builder.dart';
import '../../services/vocal_range_service.dart';
import '../../services/exercise_cache_service.dart';
import '../../services/reference_audio_cache_service.dart';
import '../../services/exercise_audio_asset_resolver.dart';
import '../../services/exercise_audio_slicer.dart';
import '../../services/audio_clock.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../services/attempt_repository.dart';
import '../../models/exercise_attempt.dart';
import 'exercise_review_summary_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/pitch_highway_painter.dart';
import '../../utils/pitch_math.dart';
import '../../utils/pitch_highway_tempo.dart';
import '../../utils/performance_clock.dart';
import '../../utils/pitch_ball_controller.dart';
import '../../utils/pitch_state.dart';
import '../../utils/pitch_visual_state.dart';
import '../../utils/pitch_tail_buffer.dart';
import '../../utils/audio_constants.dart';
import '../widgets/cents_meter.dart';
import '../../debug/debug_log.dart' show DebugLog, LogCat;
import '../../services/audio_session_service.dart';
import '../../services/pattern_spec_loader.dart';
import '../../services/pattern_visual_note_builder.dart';
import '../../models/pattern_spec.dart';

/// Buffer size for recording service.
/// 1024 samples (~23ms at 44.1kHz) is needed for reliable low-frequency pitch detection.
const int _kBufferSize = 1024;

/// Single source of truth for exercise start state
enum StartPhase { idle, starting, waitingAudio, running, stopping, done }

/// Performance tracing helper for stopwatch + DevTools Timeline spans
class PerfTrace {
  PerfTrace(this.label) : _sw = Stopwatch()..start() {
    debugPrint('[Perf] $label start');
    dev.Timeline.startSync(label);
  }
  final String label;
  final Stopwatch _sw;
  void mark(String name) {
    debugPrint('[Perf] $label +${_sw.elapsedMilliseconds}ms :: $name');
  }

  void end() {
    dev.Timeline.finishSync();
    debugPrint('[Perf] $label end @${_sw.elapsedMilliseconds}ms');
  }
}

class ExercisePlayerScreen extends StatelessWidget {
  final VocalExercise exercise;
  final PitchHighwayDifficulty? pitchDifficulty;
  final ExercisePlan? exercisePlan;

  const ExercisePlayerScreen({
    super.key,
    required this.exercise,
    this.pitchDifficulty,
    this.exercisePlan,
  });

  @override
  Widget build(BuildContext context) {
    final isPitchHighway = exercise.type == ExerciseType.pitchHighway;
    final Widget body = switch (exercise.type) {
      ExerciseType.pitchHighway => pitchDifficulty == null
          ? FutureBuilder(
              future: ExerciseLevelProgressRepository()
                  .getExerciseProgress(exercise.id),
              builder: (context, snapshot) {
                final progress = snapshot.data;
                if (snapshot.connectionState != ConnectionState.done &&
                    progress == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final resolved = progress == null
                    ? PitchHighwayDifficulty.easy
                    : pitchHighwayDifficultyFromLevel(
                        progress.highestUnlockedLevel,
                      );
                return PitchHighwayPlayer(
                  exercise: exercise,
                  showBackButton: true,
                  pitchDifficulty: resolved,
                  exercisePlan: exercisePlan,
                );
              },
            )
          : PitchHighwayPlayer(
              exercise: exercise,
              showBackButton: true,
              pitchDifficulty: pitchDifficulty ?? PitchHighwayDifficulty.medium,
              exercisePlan: exercisePlan,
            ),
      ExerciseType.breathTimer => BreathTimerPlayer(exercise: exercise),
      ExerciseType.sovtTimer => SovtTimerPlayer(exercise: exercise),
      ExerciseType.sustainedPitchHold =>
        SustainedPitchHoldPlayer(exercise: exercise),
      ExerciseType.pitchMatchListening =>
        PitchMatchListeningPlayer(exercise: exercise),
      ExerciseType.articulationRhythm =>
        ArticulationRhythmPlayer(exercise: exercise),
      ExerciseType.dynamicsRamp => DynamicsRampPlayer(exercise: exercise),
      ExerciseType.cooldownRecovery =>
        CooldownRecoveryPlayer(exercise: exercise),
    };
    return Scaffold(
      appBar: isPitchHighway
          ? null
          : AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: null,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              title: Text(exercise.name),
            ),
      body: body,
    );
  }
}

class PitchHighwayPlayer extends StatefulWidget {
  final VocalExercise exercise;
  final bool showBackButton;
  final PitchHighwayDifficulty pitchDifficulty;
  final ExercisePlan? exercisePlan;

  const PitchHighwayPlayer({
    super.key,
    required this.exercise,
    this.showBackButton = false,
    required this.pitchDifficulty,
    this.exercisePlan,
  });

  @override
  State<PitchHighwayPlayer> createState() => _PitchHighwayPlayerState();
}

class _PitchHighwayPlayerState extends State<PitchHighwayPlayer>
    with SingleTickerProviderStateMixin {
  final AudioSynthService _synth =
      AudioSynthService(); // For cached audio playback
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  final ValueNotifier<double?> _liveMidi = ValueNotifier<double?>(null);
  final List<PitchFrame> _captured = [];
  final ProgressService _progress = ProgressService();
  final LastTakeStore _lastTakeStore = LastTakeStore();
  final ExerciseLevelProgressRepository _levelProgress =
      ExerciseLevelProgressRepository();
  final PerformanceClock _clock = PerformanceClock();
  late final AudioClock _audioClock;
  final PitchBallController _pitchBall = PitchBallController();
  final PitchState _pitchState = PitchState();
  final PitchVisualState _visualState = PitchVisualState();
  final PitchTailBuffer _tailBuffer = PitchTailBuffer();
  final VocalRangeService _vocalRangeService = VocalRangeService();
  final _tailWindowSec = 4.0;
  // Use shared constant for lead-in time
  static const double _leadInSec = AudioConstants.leadInSec;
  Ticker? _ticker;

  /// Single source of truth for exercise state
  StartPhase _phase = StartPhase.idle;

  /// Derived UI flags
  bool get isStarting =>
      _phase == StartPhase.starting || _phase == StartPhase.waitingAudio;
  bool get isRunning => _phase == StartPhase.running;
  bool get _playing =>
      _phase == StartPhase.running || isStarting; // For backward compatibility
  bool get _preparing => isStarting; // For backward compatibility

  bool _audioStarted = false;
  Size? _canvasSize;
  // Y-axis mapping: set once from user's vocal range, never changes during exercise
  int _midiMin = 48; // Will be set from user's range in initState
  int _midiMax = 72; // Will be set from user's range in initState
  bool _midiRangeSet = false; // Guard to prevent changes after initial set
  int _prepRemaining = 0;
  Timer? _prepTimer;
  bool _captureEnabled = false;
  bool _useMic = true;
  RecordingService? _recording;
  StreamSubscription<PitchFrame>? _sub;
  StreamSubscription<Duration>? _audioPosSub;
  double? _scorePct;
  DateTime? _startedAt;
  bool _attemptSaved = false;
  double? _recorderStartSec;
  String? _lastRecordingPath;
  String? _lastContourJson;
  late final PitchHighwaySpec? _scaledSpec;
  late final double _tempoMultiplier;
  late final double _pixelsPerSecond;
  double? _audioPositionSec;
  double _manualOffsetMs = 0;
  late final double _audioLatencyMs;
  final double _pitchInputLatencyMs = 25;
  List<ReferenceNote> _transposedNotes = const [];
  SirenPath?
      _sirenVisualPath; // Visual path for Sirens (separate from audio notes)
  bool _notesLoaded = false;
  PatternSpec? _patternSpec; // Cached pattern spec for JSON-driven rendering
  String? _rangeError;

  // Instant start state management
  int? _tapEpochMs;
  int? _exerciseStartEpochMs;
  int? _audioPlayCalledEpochMs; // When audio.play() was called
  int? _audioPlayingEpochMs; // When audio.play() returned successfully
  int? _audioResumeCalledEpochMs; // When audio.resume() was called
  int?
      _audioProgressStartEpochMs; // When audio position actually starts advancing
  double? _seekTargetMs; // Target seek position in milliseconds
  double? _sliceStartSec; // Slice start time in seconds
  bool _isImmediateTick =
      false; // Flag to prevent double logging on immediate tick
  int _runId = 0; // Increment on each start to ignore stale async callbacks
  Key? _pitchHighwayKey; // Key to force remount of pitch highway widget
  bool _loggedFirstTick = false; // Track if we've logged the first ticker tick
  PerfTrace? _startTrace; // Store trace for ticker access
  Timer? _timingDebugTimer; // Timer for periodic timing debug logs
  bool _audioProgressDetected =
      false; // Track if audio progress has been detected

  // Per-run start guards to prevent double-starting
  bool _visualsStarted = false; // Visuals (clock/ticker) started for this run
  int?
      _timelineStartEpochMs; // Timeline anchor epoch (set once per run, never changed)
  int? _lastModelHash; // Track model identity per run
  int? _lastRepaintHash; // Track repaint notifier identity per run
  double _lastTime = 0.0; // Track last time value for backwards detection
  bool _showDebugOverlay =
      false; // Toggle for debug overlay (set to true to enable)

  double get _durationSec {
    return widget.exercisePlan?.durationSec ?? 0.0;
  }

  @override
  void initState() {
    super.initState();
    final initStartTime = DateTime.now();
    debugPrint(
        '[ExercisePlayerScreen] initState start at ${initStartTime.millisecondsSinceEpoch}');

    // Initialize MIDI engine (sets up route change listeners automatically)
    // No MIDI engine initialization needed - using cached audio instead

    // Clear all state to prevent rendering old data from previous exercise
    _transposedNotes = const [];
    _notesLoaded = false;
    _patternSpec = null; // Clear pattern spec
    _phase = StartPhase.idle;
    _setTimeValue(0.0, src: 'initState');
    _pitchBall.reset();
    _pitchState.reset();
    _visualState.reset();
    _tailBuffer.clear();
    _captured.clear();
    _scorePct = null;
    _attemptSaved = false;
    _startedAt = null;
    _audioPositionSec = null;
    _audioStarted = false;
    _tapEpochMs = null;
    _exerciseStartEpochMs = null;
    _audioPlayCalledEpochMs = null;
    _audioPlayingEpochMs = null;
    _audioResumeCalledEpochMs = null;
    _audioProgressStartEpochMs = null;
    _seekTargetMs = null;
    _sliceStartSec = null;
    _audioProgressDetected = false;
    _timingDebugTimer?.cancel();
    _timingDebugTimer = null;
    _setTimelineStartEpochMs(null, src: 'initState');
    _lastModelHash = null;
    _lastRepaintHash = null;
    _visualsStarted = false;
    _captureEnabled = false;
    _isImmediateTick = false;
    _prepRemaining = 0;
    _prepTimer = null;
    _runId = 0;
    _liveMidi.value = null;
    _setPitchHighwayKey(ValueKey('pitchHighway_$_runId'),
        src: 'initState'); // Initialize key

    // Load user's vocal range and set Y-axis mapping ONCE before any rendering
    // This ensures no visual jumps - Y-axis mapping remains constant throughout exercise
    unawaited(_loadUserVocalRange());

    _ticker = createTicker(_onTick);
    final afterTicker = DateTime.now();
    debugPrint(
        '[ExercisePlayerScreen] after createTicker: ${afterTicker.difference(initStartTime).inMilliseconds}ms');

    _scaledSpec = _buildScaledSpec();
    final afterScaledSpec = DateTime.now();
    debugPrint(
        '[ExercisePlayerScreen] after _buildScaledSpec: ${afterScaledSpec.difference(initStartTime).inMilliseconds}ms');

    _pixelsPerSecond =
        PitchHighwayTempo.pixelsPerSecondFor(widget.pitchDifficulty);
    _audioLatencyMs = kIsWeb ? 0 : (Platform.isIOS ? 100.0 : 150.0);
    _audioClock = AudioClock(_synth.player);
    _clock.setAudioPositionProvider(() => _audioPositionSec);

    // Initialize MIDI synth (load SoundFont once)
    // Engine initializes automatically on first use
    _clock.setLatencyCompensationMs(_audioLatencyMs);

    // Add frame timing callback to detect jank (only if frame timing debug enabled)
    // Frame timing is disabled by default to reduce log spam
    // Frame timing disabled to reduce log spam
    // if (kDebugPitchHighway && kDebugFrameTiming) {
    //   SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    // }

    // Prime audio player to avoid first-play latency
    _primeAudio();

    // Schedule heavy work after first frame to avoid blocking UI
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final postFrameTime = DateTime.now();
      debugPrint(
          '[ExercisePlayerScreen] postFrameCallback at ${postFrameTime.difference(initStartTime).inMilliseconds}ms');

      // Initialize recording service (but don't start yet - will start in _start())
      if (_useMic) {
        _recording = RecordingService(owner: 'exercise', bufferSize: _kBufferSize);
        debugPrint(
            '[ExercisePlayerScreen] RecordingService created (not started yet)');
      }

      // Load transposed notes asynchronously after first frame
      _loadTransposedNotes();
    });

    final initEndTime = DateTime.now();
    debugPrint(
        '[ExercisePlayerScreen] initState complete: ${initEndTime.difference(initStartTime).inMilliseconds}ms');
  }

  // Route change handlers removed - ReferenceMidiEngine handles route changes automatically via flutter_headset_detector
  // The engine will automatically resume playback using the registered playback context

  /// Handle route change or interruption during exercise
  Future<void> _handleRouteChangeDuringExercise() async {
    if (_phase != StartPhase.running) return;

    final currentTimeSec = _time.value;

    if (kDebugMode) {
      debugPrint(
          '[Exercise] Handling route change during exercise at time ${currentTimeSec.toStringAsFixed(3)}s');
    }

    // Re-apply audio session configuration
    await AudioSessionService.applyExerciseSession(
        tag: 'routeChangeDuringExercise');

    // Ensure MIDI engine is running (rebuild if needed)
    // Route changes handled automatically by ReferenceMidiEngine

    // Note: Timer-based scheduling will continue automatically after engine rebuild
    // The timers are already scheduled, so they should fire correctly once engine is rebuilt
  }

  Future<void> _loadTransposedNotes() async {
    final loadStartTime = DateTime.now();
    debugPrint(
        '[ExercisePlayerScreen] _loadTransposedNotes start at ${loadStartTime.millisecondsSinceEpoch}');

    // Show preparing state
    if (mounted) {
      setState(() {
        _notesLoaded = false;
      });
    }

    // Ensure range is loaded BEFORE generating exercise notes
    final rangeStartTime = DateTime.now();
    final (lowestMidi, highestMidi) = await _vocalRangeService.getRange();
    final rangeEndTime = DateTime.now();
    debugPrint(
        '[ExercisePlayerScreen] getRange() took ${rangeEndTime.difference(rangeStartTime).inMilliseconds}ms');

    // Validate range - do not proceed with defaults
    if (lowestMidi <= 0 || highestMidi <= 0 || lowestMidi >= highestMidi) {
      debugPrint(
          '[ExercisePlayerScreen] ERROR: Invalid vocal range - lowestMidi=$lowestMidi, highestMidi=$highestMidi');
      if (mounted) {
        setState(() {
          _notesLoaded = false;
          _rangeError =
              'Please set your vocal range in your profile to personalize exercises.';
        });
      }
      return;
    }

    // Validation logging
    debugPrint(
        '[ExercisePlayerScreen] Loaded range: lowestMidi=$lowestMidi (${PitchMath.midiToName(lowestMidi)}), highestMidi=$highestMidi (${PitchMath.midiToName(highestMidi)})');

    // Try to load pattern JSON first (same logic as _startHeavyPrepare)
    // This ensures consistency between initial load and playback start
    _patternSpec =
        await PatternSpecLoader.instance.loadPattern(widget.exercise.id);

    List<ReferenceNote> notes;
    SirenPath? sirenPath;

    if (_patternSpec != null) {
      debugPrint(
          '[ExercisePlayerScreen] Found pattern JSON for ${widget.exercise.id}, using PatternVisualNoteBuilder');
      final patternNotes = PatternVisualNoteBuilder.buildVisualNotesFromPattern(
        pattern: _patternSpec!,
        lowestMidi: lowestMidi,
        highestMidi: highestMidi,
        leadInSec: _leadInSec,
      );
      notes = patternNotes;
      sirenPath = null;
    } else {
      // Fallback: try to get cached notes
      final cacheService = ExerciseCacheService.instance;
      final cachedNotes = cacheService.getCachedNotes(
        exerciseId: widget.exercise.id,
        difficulty: widget.pitchDifficulty,
      );

      if (cachedNotes != null) {
        debugPrint(
            '[ExercisePlayerScreen] Using cached notes (${cachedNotes.length} notes)');
        notes = cachedNotes;
        // For Sirens, regenerate visual path from cached audio notes
        if (widget.exercise.id == 'sirens') {
          final sirenResult =
              TransposedExerciseBuilder.buildSirensWithVisualPath(
            exercise: widget.exercise,
            lowestMidi: lowestMidi,
            highestMidi: highestMidi,
            leadInSec: _leadInSec,
            difficulty: widget.pitchDifficulty,
          );
          sirenPath = sirenResult.visualPath;
          notes = cachedNotes;
        } else {
          sirenPath = null;
        }
      } else {
        // Fallback: generate on the fly if not cached
        debugPrint(
            '[ExercisePlayerScreen] WARNING: No cached notes found, generating on the fly');
        final buildStartTime = DateTime.now();

        // Special handling for Sirens
        if (widget.exercise.id == 'sirens') {
          final sirenResult =
              TransposedExerciseBuilder.buildSirensWithVisualPath(
            exercise: widget.exercise,
            lowestMidi: lowestMidi,
            highestMidi: highestMidi,
            leadInSec: _leadInSec,
            difficulty: widget.pitchDifficulty,
          );
          notes = sirenResult.audioNotes;
          sirenPath = sirenResult.visualPath;
        } else {
          notes = TransposedExerciseBuilder.buildTransposedSequence(
            exercise: widget.exercise,
            lowestMidi: lowestMidi,
            highestMidi: highestMidi,
            leadInSec: _leadInSec,
            difficulty: widget.pitchDifficulty,
          );
          sirenPath = null;
        }

        final buildEndTime = DateTime.now();
        debugPrint(
            '[ExercisePlayerScreen] TransposedExerciseBuilder took ${buildEndTime.difference(buildStartTime).inMilliseconds}ms');

        if (mounted) {
          setState(() {
            _sirenVisualPath = sirenPath;
          });
        }
      }
    }

    if (mounted) {
      setState(() {
        _transposedNotes = notes;
        _sirenVisualPath =
            sirenPath; // Set visual path (from cache or generation)
        _notesLoaded = true;
        _rangeError = null;
        // Y-axis mapping is set once from user's vocal range in initState
        // Do NOT adjust based on notes - this would cause visual jumps
        // _midiMin and _midiMax remain constant throughout the exercise

        // Initialize pitch ball at first target note so it appears immediately
        // This ensures the pitch ball is visible from the start, even before recording starts
        if (notes.isNotEmpty) {
          final firstNoteMidi = notes.first.midi.toDouble();
          _liveMidi.value = firstNoteMidi;
          _visualState.update(
            timeSec: 0.0,
            pitchHz: 440.0 * math.pow(2.0, (firstNoteMidi - 69) / 12.0),
            pitchMidi: firstNoteMidi,
            voiced: false, // Not voiced until user sings
          );
        }
      });

      final loadEndTime = DateTime.now();
      debugPrint(
          '[ExercisePlayerScreen] _loadTransposedNotes complete: ${loadEndTime.difference(loadStartTime).inMilliseconds}ms');

      // Initialize MIDI synth (lightweight - ensures SoundFont is loaded)
      if (notes.isNotEmpty) {
        // Engine initializes automatically on first use
      }

      // Auto-start the exercise immediately once notes are loaded
      // The 2-second lead-in is built into the notes themselves
      if (notes.isNotEmpty && _phase == StartPhase.idle) {
        // Start immediately - no delay needed
        onStartPressed();
      }
    }
  }

  // Note: _prewarmReferenceAudio is kept for compatibility but now just initializes MIDI synth

  /// Prewarm MIDI synth (ensure SoundFont is loaded)
  /// MIDI playback is instant, so we just ensure initialization
  Future<void> _prewarmReferenceAudio(List<ReferenceNote> notes) async {
    if (!mounted) return;
    try {
      // Ensure MIDI synth is initialized (idempotent)
      // No MIDI engine needed - using cached audio
      DebugLog.log(LogCat.midi, 'MIDI engine ready for ${notes.length} notes');
    } catch (e) {
      DebugLog.log(LogCat.error, 'Error initializing MIDI engine: $e');
      // Non-fatal - will retry on Start if needed
    }
  }

  PitchHighwaySpec? _buildScaledSpec() {
    final spec = widget.exercise.highwaySpec;
    final segments = spec?.segments ?? const <PitchSegment>[];
    _tempoMultiplier =
        PitchHighwayTempo.multiplierFor(widget.pitchDifficulty, segments);
    if (spec == null || spec.segments.isEmpty) return spec;
    final scaledSegments = PitchHighwayTempo.scaleSegments(
      spec.segments,
      _tempoMultiplier,
    );
    return PitchHighwaySpec(segments: scaledSegments);
  }

  /// Frame timing callback to detect jank (only logs slow frames > 50ms)
  void _onFrameTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final total = t.totalSpan.inMilliseconds;
      // Only log frames that are significantly slow (> 50ms)
      if (total > 50) {
        DebugLog.log(LogCat.perf,
            'Frame total=${total}ms build=${t.buildDuration.inMilliseconds}ms raster=${t.rasterDuration.inMilliseconds}ms');
      }
    }
  }

  @override
  void dispose() {
    // ignore: avoid_print
    print('[ExercisePlayerScreen] dispose - cleaning up resources');

    // Remove frame timing callback (only if it was added)
    // Frame timing disabled to reduce log spam
    // if (kDebugPitchHighway && kDebugFrameTiming) {
    //   SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    // }

    // Stop ticker and clock first
    _ticker?.stop();
    _ticker?.dispose();
    _clock.pause();

    // Cancel subscriptions
    _sub?.cancel();
    _sub = null;
    _audioPosSub?.cancel();
    _audioPosSub = null;

    // Stop and dispose recording service
    if (_recording != null) {
      // Stop first, then dispose asynchronously
      _recording!.stop().then((_) async {
        try {
          await _recording?.dispose();
          // ignore: avoid_print
          print('[ExercisePlayerScreen] Recording disposed');
        } catch (e) {
          // ignore: avoid_print
          print('[ExercisePlayerScreen] Error disposing recording: $e');
        }
      }).catchError((e) {
        // ignore: avoid_print
        print('[ExercisePlayerScreen] Error stopping recording: $e');
      });
      _recording = null;
    }

    // Cancel timers
    _prepTimer?.cancel();
    _prepTimer = null;

    // Stop audio
    _synth.stop();

    // Clear all state to prevent old data from persisting
    _transposedNotes = const [];
    _notesLoaded = false;
    _patternSpec = null; // Clear pattern spec
    _phase = StartPhase.idle;
    _captureEnabled = false;
    _audioStarted = false;
    _scorePct = null;
    _attemptSaved = false;
    _startedAt = null;
    _audioPositionSec = null;
    _tapEpochMs = null;
    _exerciseStartEpochMs = null;
    _audioPlayCalledEpochMs = null;
    _audioPlayingEpochMs = null;
    _audioResumeCalledEpochMs = null;
    _audioProgressStartEpochMs = null;
    _seekTargetMs = null;
    _sliceStartSec = null;
    _audioProgressDetected = false;
    _timingDebugTimer?.cancel();
    _timingDebugTimer = null;
    _timelineStartEpochMs = null;
    _visualsStarted = false;
    _isImmediateTick = false;
    _rangeError = null;
    _lastRecordingPath = null;
    _lastContourJson = null;
    _canvasSize = null;

    // Clear buffers and state objects
    _captured.clear();
    _tailBuffer.clear();
    _pitchBall.reset();
    _pitchState.reset();
    _visualState.reset();

    // Dispose value notifiers
    _time.dispose();
    _liveMidi.dispose();

    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!isRunning && !isStarting) return;

    // Drive visual time from audio clock if running
    if (isRunning && _audioClock.audioStarted) {
      final audioNow = _audioClock.nowSeconds;
      _setTimeValue(audioNow, src: 'ticker_audio');
      _audioPositionSec = audioNow;
    } else if (isStarting) {
      // Stay at 0 until audio actually starts
      _setTimeValue(0.0, src: 'ticker_waiting');
    }

    final now = _time.value;
    if (now != _lastTime) {
      _lastTime = now;
      
      // Detected progress
      if (now > 0 && !_audioProgressDetected) {
        _audioProgressDetected = true;
        _audioProgressStartEpochMs = DateTime.now().millisecondsSinceEpoch;
        DebugLog.log(LogCat.audio, 'AUDIO PROGRESS DETECTED via clock');
      }

      final effectiveMidi = _pitchState.effectiveMidi;
      final effectiveHz = _pitchState.effectiveHz;
      _visualState.update(
        timeSec: now,
        pitchHz: effectiveHz,
        pitchMidi: effectiveMidi,
        voiced: _pitchState.isVoiced,
      );
      
      final visualMidi = _visualState.visualPitchMidi;
      if (_canvasSize != null && visualMidi != null) {
        final y = PitchMath.midiToY(
          midi: visualMidi,
          height: _canvasSize!.height,
          midiMin: _midiMin,
          midiMax: _midiMax,
        );
        _tailBuffer.addPoint(tSec: now, yPx: y, voiced: _visualState.isVoiced);
        _tailBuffer.pruneOlderThan(now - _tailWindowSec);
      }

      if (!_useMic) {
        _simulatePitch(now);
      }

      _pitchState.updateUnvoiced(timeSec: now);
    }

    if (now >= _durationSec && isRunning) {
      _stop();
    }
  }

  /// Prime audio player to avoid first-play latency
  Future<void> _primeAudio() async {
    try {
      // Warm up the audio player by setting a minimal source
      // This initializes the audio engine without playing anything
      await _synth.stop(); // Ensure clean state
    } catch (e) {
      debugPrint('[ExercisePlayerScreen] Error priming audio: $e');
    }
  }

  /// Load user's vocal range and set Y-axis mapping once before exercise begins
  /// This ensures Y-axis mapping is constant and prevents visual jumps
  Future<void> _loadUserVocalRange() async {
    if (_midiRangeSet) return; // Already set, don't change

    try {
      final (lowestMidi, highestMidi) = await VocalRangeService().getRange();
      if (mounted && !_midiRangeSet) {
        setState(() {
          // Add 3 semitones of visual padding to top and bottom as requested
          // This ensures notes don't appear at the very edges of the screen
          const paddingMidi = 3;
          _midiMin = lowestMidi - paddingMidi;
          _midiMax = highestMidi + paddingMidi;
          _midiRangeSet = true;
        });
        debugPrint(
            '[ExercisePlayerScreen] Y-axis mapping set: $_midiMin - $_midiMax (user range $lowestMidi-$highestMidi + 3 padding)');
      }
    } catch (e) {
      debugPrint('[ExercisePlayerScreen] Error loading vocal range: $e');
      // Keep default values (48-72) if loading fails
      if (mounted && !_midiRangeSet) {
        setState(() {
          _midiRangeSet =
              true; // Mark as set even with defaults to prevent retry
        });
      }
    }
  }

  /// Hard-reset ALL runtime state used by the pitch highway.
  /// Called on Start press to ensure a clean slate.
  void _resetRunState() {
    _runId++;

    // Stop ticker and clock
    _ticker?.stop();
    _clock.pause();

    // Cancel subscriptions (but don't block - will be replaced)
    _sub?.cancel();
    _sub = null;
    _audioPosSub?.cancel();
    _audioPosSub = null;

    // Reset all runtime flags
    _phase = StartPhase.idle;
    _captureEnabled = false;
    _audioStarted = false;
    _isImmediateTick = false;

    // Reset per-run start guards
    _visualsStarted = false;
    _lastModelHash = null;
    _lastRepaintHash = null;

    // Reset timestamps
    _tapEpochMs = null;
    _exerciseStartEpochMs = null;
    _audioPlayCalledEpochMs = null;
    _audioPlayingEpochMs = null;
    _audioResumeCalledEpochMs = null;
    _audioProgressStartEpochMs = null;
    _seekTargetMs = null;
    _sliceStartSec = null;
    _audioProgressDetected = false;
    _timingDebugTimer?.cancel();
    _timingDebugTimer = null;
    _setTimelineStartEpochMs(null,
        src: '_resetRunState'); // Reset timeline anchor
    _startedAt = null;
    _audioPositionSec = null;

    // Reset score and attempt state
    _scorePct = null;
    _attemptSaved = false;

    // Reset time to 0 (only allowed here)
    _setTimeValue(0.0, src: '_resetRunState');
    _liveMidi.value = null;

    // Clear all buffers and collections
    _captured.clear();
    _tailBuffer.clear();

    // Reset state objects
    _pitchBall.reset();
    _pitchState.reset();
    _visualState.reset();

    // Cancel prep timer and any other timers
    _prepTimer?.cancel();
    _prepTimer = null;
    _prepRemaining = 0;

    // Force pitch highway widget to remount with new key (only allowed in reset)
    _setPitchHighwayKey(ValueKey('pitchHighway_$_runId'),
        src: '_resetRunState');

    // Reset first tick logging flag
    _loggedFirstTick = false;

    // Log repaint listenable replacement
    // CRITICAL: repaint listenable is always _time (stable, never changes within a run)
    DebugLog.log(LogCat.lifecycle,
        'Run state cleared, runId=$_runId, repaintListenable=${_time.hashCode}');

    // Log model/notifier identities (if we had a model, but we use ValueNotifiers directly)
    DebugLog.log(LogCat.lifecycle,
        'timeNotifier=${_time.hashCode} liveMidiNotifier=${_liveMidi.hashCode}');

    // Log that scroll/time are reset (should only happen here)
    DebugLog.log(LogCat.lifecycle, 'scroll/time reset to 0 (runId=$_runId)');

    // Reset time tracking for backwards detection
    _lastTime = 0.0;
  }

  /// Tripwire: Set time value with source tracking
  void _setTimeValue(double v, {required String src}) {
    if (v == 0.0 && _playing) {
      DebugLog.tripwire(
          LogCat.lifecycle, 'time reset to 0 src=$src runId=$_runId');
    }
    _time.value = v;
  }

  /// Tripwire: Set timeline start epoch with source tracking
  /// CRITICAL: This should only be set ONCE per run (in onStartPressed or _ensureVisualsStarted)
  /// Any change after start is a bug and will cause time to jump backwards
  void _setTimelineStartEpochMs(int? v, {required String src}) {
    if (v != null &&
        _timelineStartEpochMs != null &&
        _timelineStartEpochMs != v) {
      // This is a bug - timeline anchor should never change after start
      DebugLog.tripwire(LogCat.error, 'timeline_changed',
          message:
              'timelineStartEpochMs CHANGED from $_timelineStartEpochMs to $v src=$src runId=$_runId',
          runId: _runId);
    } else if (v != null && _playing) {
      // Setting timeline anchor while playing is also a bug
      DebugLog.tripwire(LogCat.error, 'timeline_set_while_playing',
          message:
              'timelineStartEpochMs set to $v src=$src runId=$_runId WHILE PLAYING',
          runId: _runId);
    } else if (v != null) {
      DebugLog.event(LogCat.lifecycle, 'timeline_set',
          runId: _runId, fields: {'value': v, 'src': src});
    }
    _timelineStartEpochMs = v;
  }

  /// Tripwire: Set pitch highway key with source tracking
  void _setPitchHighwayKey(Key key, {required String src}) {
    if (_pitchHighwayKey != null && _pitchHighwayKey != key && _playing) {
      DebugLog.tripwire(LogCat.error, 'key_changed',
          message:
              'pitchHighwayKey CHANGED from $_pitchHighwayKey to $key src=$src runId=$_runId',
          runId: _runId);
    } else if (_pitchHighwayKey != key) {
      DebugLog.event(LogCat.lifecycle, 'key_set',
          runId: _runId, fields: {'key': key.toString(), 'src': src});
    }
    _pitchHighwayKey = key;
  }

  /// Called immediately when user taps Start - no awaits, instant UI response
  void onStartPressed() {
    if (isStarting || isRunning || _phase == StartPhase.stopping) {
      debugPrint('[Start] Ignored - phase=$_phase');
      return;
    }

    final tapTime = DateTime.now();
    final t0 = tapTime.millisecondsSinceEpoch;
    debugPrint('[Start] tap at $t0');

    // Debug instrumentation: log start button tap
    if (kDebugMode) {
      debugPrint(
          '[TIMING_DEBUG] [1] START_BUTTON_TAP runId=${_runId + 1} tapEpochMs=$t0');
    }

    // Create performance trace for this start
    final trace = PerfTrace('StartExercise runId=${_runId + 1}');
    trace.mark('tap');
    _startTrace = trace; // Store for ticker access

    // CRITICAL: Reset ALL state FIRST in setState to ensure clean UI render
    debugPrint('[Start] BEFORE setState runId=$_runId');

    // Compute timeline start epoch ONCE (this is the anchor, never changes)
    // Offset by -200ms so visual time is 0.2s ahead of real time
    // This makes notes intersect playhead at 2.2s visual time while audio starts at 2.0s real time
    final visualLeadTimeMs = -300; // 0.2 seconds
    final timelineStartMs =
        t0 - visualLeadTimeMs; // Start 0.2s earlier for visual offset

    setState(() {
      _resetRunState(); // Clears all runtime state, increments runId, creates new key
      _tapEpochMs = t0;
      _exerciseStartEpochMs =
          t0 + 120; // Small buffer for audio/mic spin up (for reference only)
      _setTimelineStartEpochMs(timelineStartMs,
          src: 'onStartPressed'); // Set timeline anchor ONCE
      _startedAt = tapTime;
      _phase = StartPhase
          .starting; // Set phase to starting - stays true until audio plays
      DebugLog.event(LogCat.lifecycle, 'phase_starting',
          runId: _runId, fields: {'tap': t0});
    });

    trace.mark('after reset setState');
    debugPrint('[Start] AFTER setState runId=$_runId phase=$_phase');

    // Start visuals immediately (no awaits) - idempotent, will only start once
    _ensureVisualsStarted(runId: _runId, startEpochMs: timelineStartMs);
    trace.mark('after ensureVisualsStarted');

    // Start fast engines immediately (recorder, mic access) - does NOT change phase
    final currentRunId = _runId;
    unawaited(_startFastEngines(runId: currentRunId, t0: t0, trace: trace));

    // CRITICAL: Schedule heavy audio preparation AFTER first frame paints
    // This ensures the clean-slate UI is visible immediately before heavy work begins
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[Start] FIRST FRAME AFTER RESET PAINTED runId=$_runId');
      trace.mark('first frame after reset painted');
      unawaited(_startHeavyPrepare(runId: currentRunId, t0: t0, trace: trace));
    });
  }

  /// Ensure visuals are started exactly once per run (idempotent)
  /// Must NOT clear scroll, buffers, or reset notifiers - those belong in _resetRunState()
  void _ensureVisualsStarted({required int runId, required int startEpochMs}) {
    if (runId != _runId) {
      debugPrint(
          '[Visuals] _ensureVisualsStarted ignored - runId mismatch ($runId != $_runId)');
      return;
    }
    if (_visualsStarted) {
      debugPrint(
          '[Visuals] _ensureVisualsStarted ignored - already started (runId=$runId)');
      return;
    }

    _visualsStarted = true;

    // CRITICAL: Timeline anchor should already be set in onStartPressed
    // Only set it here if it's somehow not set (shouldn't happen)
    if (_timelineStartEpochMs == null) {
      DebugLog.tripwire(LogCat.error, 'timeline_missing',
          message:
              'timelineStartEpochMs was null in _ensureVisualsStarted, setting to $startEpochMs runId=$runId',
          runId: runId);
      _setTimelineStartEpochMs(startEpochMs,
          src: '_ensureVisualsStarted_fallback');
    } else if (_timelineStartEpochMs != startEpochMs) {
      // This is a bug - anchor should match what was set in onStartPressed
      DebugLog.tripwire(LogCat.error, 'timeline_mismatch',
          message:
              'timelineStartEpochMs mismatch: stored=$_timelineStartEpochMs passed=$startEpochMs runId=$runId',
          runId: runId);
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    debugPrint(
        '[Visuals] started once runId=$runId startEpoch=$startEpochMs (at $nowMs)');

    // Debug instrumentation: log visuals start
    if (kDebugMode) {
      debugPrint(
          '[TIMING_DEBUG] [2] VISUALS_START runId=$runId visualsStartEpochMs=$nowMs');
    }

    // Start clock immediately so visuals move during lead-in
    // Visuals will slide toward playline during the 2-second lead-in
    _clock.setLatencyCompensationMs(_audioLatencyMs + _manualOffsetMs);

    // Start clock immediately (no freezing) - visuals begin moving right away
    _clock.start(offsetSec: 0.0, freezeUntilAudio: false);

    // Start ticker (but clock is frozen, so visuals won't advance yet)
    DebugLog.event(LogCat.lifecycle, 'ticker_start', runId: runId);
    _ticker?.start();

    // Log post-frame after ticker.start()
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint(
          '[Visuals] postFrame after ticker.start at ${DateTime.now().millisecondsSinceEpoch}');
    });

    // Force immediate first tick to render visuals right away (don't wait for next frame)
    _isImmediateTick = true; // Mark as immediate to prevent double logging
    _onTick(Duration.zero);

    final afterVisuals = DateTime.now();
    debugPrint(
        '[Visuals] visuals started <= ${afterVisuals.millisecondsSinceEpoch - startEpochMs}ms');
  }

  /// Called when audio begins progressing (for logging/debugging only)
  /// Visual clock already started immediately, so no anchor adjustment needed
  void _startVisualClockOnAudioProgress(
      {required int runId, required double audioPosMs}) {
    if (runId != _runId) return; // Ignore stale callbacks

    if (_timelineStartEpochMs == null) {
      debugPrint(
          '[TIMING_DEBUG] ERROR: timelineStartEpochMs is null when audio progresses');
      return;
    }

    // Visual clock already started immediately at tap time
    // Timeline anchor is already set correctly, no adjustment needed
    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
    final audioPosSec = audioPosMs / 1000.0;
    final visualTimeSec = (nowEpochMs - _timelineStartEpochMs!) / 1000.0;

    if (kDebugMode) {
      debugPrint(
          '[TIMING_DEBUG] [5] AUDIO_STARTED runId=$runId nowEpochMs=$nowEpochMs audioPosSec=${audioPosSec.toStringAsFixed(3)} visualTimeSec=${visualTimeSec.toStringAsFixed(3)}');
    }
  }

  /// Start periodic debug logging timer (first 5 seconds or until leadInSec+1.0)
  void _startTimingDebugTimer({required int runId}) {
    _timingDebugTimer?.cancel();
    int logCount = 0;
    _timingDebugTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (runId != _runId || !mounted) {
        timer.cancel();
        return;
      }

      final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
      final visualTimeSec = _time.value;
      final audioPosMs =
          _audioPositionSec != null ? _audioPositionSec! * 1000.0 : null;
      // Get audio state (simplified - just check if we have position)
      final audioState = _audioPositionSec != null ? 'playing' : 'unknown';

      // Get first note position for logging
      double? firstNoteStartSec;
      double? firstNoteLeftX;
      double? playlineX;
      double? dx;

      if (_transposedNotes.isNotEmpty) {
        firstNoteStartSec = _transposedNotes
            .map((n) => n.startSec)
            .reduce((a, b) => a < b ? a : b);
        // Calculate note X position (simplified - actual calculation is in painter)
        // This is approximate for logging purposes
        if (_canvasSize != null && _pixelsPerSecond > 0) {
          final playlineFraction = 0.35; // Match painter
          playlineX = _canvasSize!.width * playlineFraction;
          firstNoteLeftX = playlineX +
              (firstNoteStartSec - visualTimeSec) * _pixelsPerSecond;
          dx = firstNoteLeftX - playlineX;
        }
      }

      // Stop logging after leadInSec+1.0 or 5 seconds, or when dx crosses 0
      final shouldStop = visualTimeSec > _leadInSec + 1.0 ||
          visualTimeSec > 5.0 ||
          (dx != null && dx > 0 && logCount > 10); // Stop after dx crosses 0



      if (shouldStop) {
        timer.cancel();
        _timingDebugTimer = null;
      }
    });
  }

  /// Fast engine start: mic access, recording (no heavy CPU work)
  /// This runs immediately to start recording as fast as possible
  /// IMPORTANT: Does NOT change phase - phase stays in "starting" until audio plays
  Future<void> _startFastEngines(
      {required int runId, required int t0, required PerfTrace trace}) async {
    try {
      trace.mark('_startEngines begin');
      debugPrint(
          '[Start] _startEngines called at ${DateTime.now().millisecondsSinceEpoch - t0}ms (runId=$runId)');

      // Check runId after each await to ignore stale callbacks
      if (runId != _runId) {
        debugPrint('[Start] Aborted - runId mismatch ($runId != $_runId)');
        trace.mark('abort - runId mismatch');
        trace.end();
        return;
      }

      if (_useMic) {
        // Recording service should already be initialized
        if (_recording == null) {
          trace.mark('creating RecordingService');
          debugPrint('[Start] Creating RecordingService in _startEngines()');
          // Increase buffer size to _kBufferSize for better low-end pitch detection
          // 512 samples (~11.6ms) is too short for reliable detection below ~100Hz
          _recording = RecordingService(owner: 'exercise', bufferSize: _kBufferSize);
        }

        // Stop any existing recording first
        trace.mark('before recorder.stop');
        dev.Timeline.startSync('recorder.stop');
        try {
          await _recording?.stop();
          debugPrint('[Start] Stopped existing recording');
        } catch (e) {
          // Not recording, that's fine
        }
        dev.Timeline.finishSync();
        trace.mark('after recorder.stop');

        if (runId != _runId) {
          debugPrint('[Start] Aborted after stop - runId mismatch');
          trace.mark('abort after recorder.stop');
          trace.end();
          return;
        }

        // Start recording - this includes mic access request
        trace.mark('before recorder.start');
        dev.Timeline.startSync('recorder.start');
        final beforeRecorder = DateTime.now();
        _recorderStartSec = _time.value; // Use master visual exercise time as anchor
        await _recording?.start();
        final afterRecorder = DateTime.now();
        dev.Timeline.finishSync();
        trace.mark('after recorder.start');
        debugPrint(
            '[Start] recorder started at ${afterRecorder.difference(beforeRecorder).inMilliseconds}ms');

        if (runId != _runId) {
          debugPrint('[Start] Aborted after recorder start - runId mismatch');
          trace.mark('abort after recorder.start');
          trace.end();
          return;
        }

        // Cancel any existing subscription
        trace.mark('before cancel subscription');
        await _sub?.cancel();
        trace.mark('after cancel subscription');

        // Capture runId in closure to guard against stale callbacks
        final localRunId = runId;
        trace.mark('before listen to stream');
        _sub = _recording?.liveStream.listen((frame) {
          // Ignore stale data from previous runs
          if (localRunId != _runId) {
            DebugLog.log(LogCat.recorder,
                '[Stale] ignored pitch frame from runId=$localRunId current=$_runId',
                key: 'stale_pitch_frame', throttleMs: 1000, runId: localRunId);
            return;
          }
          if (!_captureEnabled) return;

          final midi = frame.midi ??
              (frame.hz != null
                  ? 69 + 12 * math.log(frame.hz! / 440.0) / math.ln2
                  : null);

          // frame.time is natively relative to the start of the audio file (t=0)
          // For LIVE synchronization with the absolute exercise time, we add the anchor.
          final absoluteNow = (_recorderStartSec ?? 0.0) + frame.time;

          final voiced = midi != null &&
              (frame.voicedProb ?? 1.0) >= 0.6 &&
              (frame.rms ?? 1.0) >= 0.02;
          double? filtered;
          if (voiced) {
            _pitchBall.addSample(timeSec: absoluteNow, midi: midi);
            filtered = _pitchBall.lastSampleMidi ?? midi;
            _pitchState.updateVoiced(
                timeSec: absoluteNow, pitchHz: frame.hz, pitchMidi: filtered);
          } else {
            _pitchState.updateUnvoiced(timeSec: absoluteNow);
          }

          // Use the file-relative time for storage to ensure audio sync on replay
          final pf = PitchFrame(
            time: frame.time,
            hz: frame.hz,
            midi: voiced ? filtered : null,
            voicedProb: frame.voicedProb,
            rms: frame.rms,
          );
          _captured.add(pf);
        });
        trace.mark('after listen to stream');
      }

      // Fast engines started - recording is ready
      trace.mark('fast engines complete');
      debugPrint('[Start] fast engines complete (runId=$runId)');
    } catch (e, stackTrace) {
      debugPrint('[Start] ERROR in _startFastEngines: $e');
      debugPrint('[Start] Stack trace: $stackTrace');
      trace.mark('ERROR in fast engines: $e');
      // Don't end trace here - heavy prepare will handle it
    }
  }

  /// Schedule and start real-time MIDI playback (lightweight, no rendering)
  /// This is scheduled AFTER the first reset frame paints to avoid blocking UI
  Future<void> _startHeavyPrepare(
      {required int runId, required int t0, required PerfTrace trace}) async {
    try {
      trace.mark('_startHeavyPrepare begin');
      debugPrint('[Start] _startHeavyPrepare called (runId=$runId)');

      if (runId != _runId) {
        debugPrint('[Start] Aborted - runId mismatch ($runId != $_runId)');
        trace.mark('abort - runId mismatch');
        trace.end();
        return;
      }

      final plan = widget.exercisePlan;
      if (plan == null) {
        throw Exception('Dynamic Reference Pipeline requires an ExercisePlan');
      }

      // Use notes from plan
      _transposedNotes = plan.notes;
      _notesLoaded = true;

      debugPrint('[Start] Using dynamic plan notes: ${plan.notes.length}');

      // Schedule Dynamic WAV Playback
      trace.mark('before playReferenceWav');
      _audioPlayCalledEpochMs = DateTime.now().millisecondsSinceEpoch;
      dev.Timeline.startSync('audio.playReferenceWav');
      
      final beforeAudio = DateTime.now();
      try {
        // Start recording alignment
        // Dynamic reference starts at 0, hardware clock provides sample-accurate position.
        _recorderStartSec = 0.0; 

        // Start playing the synthesized WAV
        await _synth.playFile(plan.wavFilePath);
        
        final afterAudio = DateTime.now();
        _audioPlayingEpochMs = afterAudio.millisecondsSinceEpoch;
        final audioSpinMs = _audioPlayingEpochMs! - _audioPlayCalledEpochMs!;
        debugPrint('[Start] audio playing, spinUp=${audioSpinMs}ms');
        trace.mark('audio playing (spinUp=${audioSpinMs}ms)');

        if (runId != _runId) {
          debugPrint('[Start] Aborted after play - runId mismatch');
          await _synth.stop();
          trace.mark('abort after play');
          trace.end();
          return;
        }

        if (mounted && runId == _runId) {
          setState(() {
            _phase = StartPhase.running;
            _audioStarted = true;
            _captureEnabled = true;
          });
          DebugLog.event(LogCat.lifecycle, 'phase_running',
              runId: runId, fields: {'spinUp': audioSpinMs});
          trace.mark('set running');
        }

      } catch (e) {
        debugPrint('[Start] audio playback FAILED: $e');
        trace.mark('ERROR playing audio: $e');
        if (runId == _runId && mounted) {
          setState(() {
            _phase = StartPhase.running;
            _captureEnabled = true;
          });
        }
      } finally {
        dev.Timeline.finishSync();
      }

      trace.mark('heavy prepare complete');
      trace.end();
    } catch (e, stackTrace) {
      debugPrint('[Start] ERROR in _startHeavyPrepare: $e');
      debugPrint('[Start] Stack trace: $stackTrace');
      trace.mark('ERROR: $e');
      trace.end();
      // Revert to idle state on error (only if still current run)
      if (runId == _runId && mounted) {
        setState(() {
          _phase = StartPhase.idle;
        });
        _ticker?.stop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start exercise: $e')),
        );
      }
    }
  }


  Future<void> _stop() async {
    if (_phase == StartPhase.stopping ||
        _phase == StartPhase.done ||
        (_phase == StartPhase.idle && !isStarting)) return;

    setState(() {
      _phase = StartPhase.stopping;
    });
    DebugLog.event(LogCat.lifecycle, 'phase_stopping', runId: _runId);
    _endPrepCountdown();
    _captureEnabled = false;
    _ticker?.stop();

    // Stop engines
    await _sub?.cancel();
    _sub = null;
    await _audioPosSub?.cancel();
    _audioPosSub = null;
    debugPrint('[Stop] stopping recording');
    final recordingResult =
        _recording == null ? null : await _recording!.stop();
    // Note: Do NOT dispose recording here - only dispose in dispose()
    await _synth.stop();
    // No MIDI engine stop needed - we're using cached audio, not MIDI
    _clock.pause();
    _pitchState.reset();
    _visualState.reset();
    _tailBuffer.clear();

    final audioPath = recordingResult?.audioPath;
    await _saveLastTake(audioPath);
    _lastRecordingPath =
        (audioPath != null && audioPath.isNotEmpty) ? audioPath : null;
    _lastContourJson = _buildContourJson();
    final score = _scorePct ?? _computeScore();
    _scorePct = score;

    setState(() {
      _phase = StartPhase.done;
    });
    DebugLog.event(LogCat.lifecycle, 'phase_done', runId: _runId);
    await _completeAndPop(score, {'intonation': score});
  }

  Future<bool> _handleExit() async {
    if (isStarting || isRunning) {
      await _stop();
      return false;
    }
    return true;
  }

  Future<void> _saveLastTake(String? audioPath) async {
    if (_captured.isEmpty) return;
    final duration = _time.value.isFinite ? _time.value : 0.0;
    final sanitized = _captured.map((f) {
      final midi = f.midi ?? (f.hz != null ? PitchMath.hzToMidi(f.hz!) : null);
      return PitchFrame(
        time: f.time,
        hz: f.hz,
        midi: midi,
        voicedProb: f.voicedProb,
        rms: f.rms,
      );
    }).toList();
    final take = LastTake(
      exerciseId: widget.exercise.id,
      recordedAt: DateTime.now(),
      frames: sanitized,
      durationSec: duration.clamp(0.0, _durationSec),
      audioPath: (audioPath != null && audioPath.isNotEmpty) ? audioPath : null,
      pitchDifficulty: widget.pitchDifficulty.name,
    );
    await _lastTakeStore.saveLastTake(take);
  }

  String? _buildContourJson() {
    if (_captured.isEmpty) return null;
    try {
      final sanitized = _captured.map((f) {
        final midi =
            f.midi ?? (f.hz != null ? PitchMath.hzToMidi(f.hz!) : null);
        return {
          't': f.time,
          'hz': f.hz,
          'midi': midi,
          'v': f.voicedProb,
          'rms': f.rms,
        };
      }).toList();
      return jsonEncode(sanitized);
    } catch (_) {
      return null;
    }
  }

  String? _buildTargetNotesJson() {
    final notes = _buildReferenceNotes();
    if (notes.isEmpty) return null;
    try {
      final targetNotes = notes.map((n) {
        return {
          'startMs': (n.startSec * 1000).round(),
          'endMs': (n.endSec * 1000).round(),
          'midi': n.midi.toDouble(),
          'label': n.lyric,
        };
      }).toList();
      return jsonEncode(targetNotes);
    } catch (_) {
      return null;
    }
  }

  String? _buildSegmentsJson() {
    final notes = _buildReferenceNotes();
    if (notes.isEmpty) return null;
    try {
      final segments = <Map<String, dynamic>>[];

      // Get the base root MIDI from the original exercise spec
      final spec = _scaledSpec;
      if (spec == null || spec.segments.isEmpty) return null;
      final baseRootMidi =
          spec.segments.first.startMidi ?? spec.segments.first.midiNote;

      // Special handling for octave slides: combine bottom note + silence + top note into one segment
      final isOctaveSlides = widget.exercise.id == 'octave_slides';

      if (isOctaveSlides) {
        // For octave slides, detect pairs of notes that are ~12 semitones apart
        // Pattern: bottom note, ~1s gap, top note (12 semitones higher), then repeat
        var segmentIndex = 0;
        var i = 0;

        while (i < notes.length) {
          final bottomNote = notes[i];
          final bottomMidi = bottomNote.midi.round();

          // Look ahead for the top note (should be ~12 semitones higher and start after ~1s gap)
          int? topNoteIndex;
          for (var j = i + 1; j < notes.length; j++) {
            final candidate = notes[j];
            final gap = candidate.startSec - bottomNote.endSec;
            final midiDiff = candidate.midi.round() - bottomMidi;

            // Top note should be ~12 semitones higher and start after ~0.8-1.2s gap
            if (gap >= 0.8 && gap <= 1.2 && midiDiff >= 11 && midiDiff <= 13) {
              topNoteIndex = j;
              break;
            }

            // If we've gone too far (gap > 1.5s or different transposition), stop looking
            if (gap > 1.5 || midiDiff < 0) {
              break;
            }
          }

          if (topNoteIndex != null) {
            // Found a pair: combine bottom note + gap + top note into one segment
            final topNote = notes[topNoteIndex];
            final transpose = bottomMidi - baseRootMidi;

            segments.add({
              'segmentIndex': segmentIndex,
              'startMs': (bottomNote.startSec * 1000).round(),
              'endMs': (topNote.endSec * 1000).round(),
              'transposeSemitone': transpose,
            });

            segmentIndex++;
            i = topNoteIndex + 1; // Move past the top note
          } else {
            // No matching top note found, treat as a regular segment
            final transpose = bottomMidi - baseRootMidi;
            segments.add({
              'segmentIndex': segmentIndex,
              'startMs': (bottomNote.startSec * 1000).round(),
              'endMs': (bottomNote.endSec * 1000).round(),
              'transposeSemitone': transpose,
            });
            segmentIndex++;
            i++;
          }
        }
      } else if (widget.exercise.id == 'sirens') {
        // Special handling for Sirens: each cycle is 3 notes (bottom, top, bottom)
        // Group notes into cycles: detect pattern of 3 notes where first and last are the same
        var segmentIndex = 0;
        var i = 0;

        while (i < notes.length) {
          if (i + 2 >= notes.length) break; // Need at least 3 notes for a cycle

          final bottom1 = notes[i];
          final top = notes[i + 1];
          final bottom2 = notes[i + 2];

          // Check if this looks like a Sirens cycle: first and last notes should be the same MIDI
          final bottom1Midi = bottom1.midi.round();
          final bottom2Midi = bottom2.midi.round();
          final topMidi = top.midi.round();

          // Verify: bottom1 and bottom2 should be the same, and top should be higher
          if (bottom1Midi == bottom2Midi && topMidi > bottom1Midi) {
            // This is a Sirens cycle: bottom → top → bottom
            final transpose = bottom1Midi - baseRootMidi;
            segments.add({
              'segmentIndex': segmentIndex,
              'startMs': (bottom1.startSec * 1000).round(),
              'endMs': (bottom2.endSec * 1000).round(),
              'transposeSemitone': transpose,
            });
            segmentIndex++;
            i += 3; // Move past all 3 notes
          } else {
            // Not a valid cycle, treat as regular segment
            final transpose = bottom1Midi - baseRootMidi;
            segments.add({
              'segmentIndex': segmentIndex,
              'startMs': (bottom1.startSec * 1000).round(),
              'endMs': (bottom1.endSec * 1000).round(),
              'transposeSemitone': transpose,
            });
            segmentIndex++;
            i++;
          }
        }
      } else {
        // Regular segment detection: find gaps > 0.5 seconds (gap between repetitions)
        var segmentIndex = 0;
        var currentSegmentStartMs = (notes.first.startSec * 1000).round();

        for (var i = 1; i < notes.length; i++) {
          final prevNote = notes[i - 1];
          final currNote = notes[i];
          final gap = currNote.startSec - prevNote.endSec;

          // New segment if gap > 0.5s (gap between repetitions)
          if (gap > 0.5) {
            // Save previous segment
            final segmentTranspose = prevNote.midi.round() - baseRootMidi;
            segments.add({
              'segmentIndex': segmentIndex,
              'startMs': currentSegmentStartMs,
              'endMs': (prevNote.endSec * 1000).round(),
              'transposeSemitone': segmentTranspose,
            });

            // Start new segment
            segmentIndex++;
            currentSegmentStartMs = (currNote.startSec * 1000).round();
          }
        }

        // Add final segment
        if (notes.isNotEmpty) {
          final lastNote = notes.last;
          final segmentTranspose = lastNote.midi.round() - baseRootMidi;
          segments.add({
            'segmentIndex': segmentIndex,
            'startMs': currentSegmentStartMs,
            'endMs': (lastNote.endSec * 1000).round(),
            'transposeSemitone': segmentTranspose,
          });
        }
      }

      return jsonEncode(segments);
    } catch (e) {
      debugPrint('Error building segments JSON: $e');
      return null;
    }
  }

  void _simulatePitch(double t) {
    // TODO: Replace simulation with real pitch stream if mic is unavailable.
    if (!_captureEnabled) return;
    final targetMidi = _targetMidiAtTime(t);
    if (targetMidi == null) return;
    final vibrato = math.sin(t * 2 * math.pi * 5) * 0.2;
    final midi = targetMidi + vibrato;
    final hz = 440.0 * math.pow(2.0, (midi - 69) / 12.0);
    _pitchBall.addSample(timeSec: t, midi: midi);
    final filtered = _pitchBall.lastSampleMidi ?? midi;
    _pitchState.updateVoiced(timeSec: t, pitchHz: hz, pitchMidi: filtered);
    _visualState.update(
        timeSec: t, pitchHz: hz, pitchMidi: filtered, voiced: true);
    
    final relativeT = _recorderStartSec != null ? (t - _recorderStartSec!) : t;
    final pf = PitchFrame(time: relativeT, hz: hz, midi: filtered);
    _captured.add(pf);
  }

  void _endPrepCountdown() {
    // No-op: phase-based state doesn't need this
    _prepTimer?.cancel();
    _prepTimer = null;
    _prepRemaining = 0;
  }

  double? _targetMidiAtTime(double t) {
    // Use transposed notes if available, otherwise fall back to old method
    if (_transposedNotes.isNotEmpty) {
      for (final note in _transposedNotes) {
        if (t >= note.startSec && t <= note.endSec) {
          return note.midi.toDouble();
        }
      }
      return null;
    }
    // Fallback to old method
    final spec = _scaledSpec;
    if (spec == null) return null;
    final adjusted = t - _leadInSec;
    if (adjusted < 0) return null;
    final ms = (adjusted * 1000).round();
    for (final seg in spec.segments) {
      if (ms < seg.startMs || ms > seg.endMs) continue;
      if (seg.isGlide) {
        final start = seg.startMidi ?? seg.midiNote;
        final end = seg.endMidi ?? seg.midiNote;
        final ratio = (ms - seg.startMs) / math.max(1, seg.endMs - seg.startMs);
        return (start + (end - start) * ratio).toDouble();
      }
      return seg.midiNote.toDouble();
    }
    return null;
  }

  List<ReferenceNote> _buildReferenceNotes() {
    // Return the transposed sequence if available (pattern-based or old method)
    if (_transposedNotes.isNotEmpty) {
      return _transposedNotes;
    }

    // Try to load pattern-based notes if pattern spec is available
    if (_patternSpec != null) {
      // Pattern notes should already be built and stored in _transposedNotes
      // If we reach here, pattern loading might have failed, fall through to old method
      debugPrint(
          '[PatternNotes] Pattern spec available but notes not built yet');
    }

    // Fallback to old method if notes aren't loaded yet
    final spec = _scaledSpec;
    if (spec == null) return const [];
    final notes = <ReferenceNote>[];
    final isNgSlides = widget.exercise.id == 'ng_slides';
    final isSirens = widget.exercise.id == 'sirens';

    for (var i = 0; i < spec.segments.length; i++) {
      final seg = spec.segments[i];
      final isGlide = seg.isGlide;

      // For NG Slides and Sirens: create full-length notes for audio, but mark for visual glide
      if ((isNgSlides || isSirens) && isGlide) {
        final endMidi = seg.endMidi ?? seg.midiNote;
        final isFirstSegment = i == 0;

        // Create full-length note for audio playback
        notes.add(ReferenceNote(
          startSec: seg.startMs / 1000.0 + _leadInSec,
          endSec: seg.endMs / 1000.0 + _leadInSec,
          midi: seg.midiNote, // Use the segment's midiNote for audio
          lyric: seg.label,
          // Mark first glide segment as glide start for visual rendering
          isGlideStart: isFirstSegment,
          glideEndMidi: isFirstSegment ? endMidi : null,
        ));
      } else if (isGlide && !isNgSlides && !isSirens) {
        // For other glides: create endpoint notes (original behavior)
        final startMidi = seg.startMidi ?? seg.midiNote;
        final endMidi = seg.endMidi ?? seg.midiNote;

        // Start endpoint note
        notes.add(ReferenceNote(
          startSec: seg.startMs / 1000.0 + _leadInSec,
          endSec: seg.startMs / 1000.0 + _leadInSec + 0.01,
          midi: startMidi,
          lyric: seg.label,
          isGlideStart: true,
          glideEndMidi: endMidi,
        ));

        // End endpoint note
        notes.add(ReferenceNote(
          startSec: seg.endMs / 1000.0 + _leadInSec - 0.01,
          endSec: seg.endMs / 1000.0 + _leadInSec,
          midi: endMidi,
          lyric: seg.label,
          isGlideEnd: true,
        ));
      } else {
        // Regular non-glide note
        notes.add(ReferenceNote(
          startSec: seg.startMs / 1000.0 + _leadInSec,
          endSec: seg.endMs / 1000.0 + _leadInSec,
          midi: seg.midiNote,
          lyric: seg.label,
        ));
      }
    }

    // For Sirens: mark the top note (second) as glide end for first glide, and last note as glide end for second glide
    if (isSirens && notes.length >= 3) {
      // First glide: bottom1 -> top (top note should be marked as glide end)
      final topNote = notes[1];
      notes[1] = ReferenceNote(
        startSec: topNote.startSec,
        endSec: topNote.endSec,
        midi: topNote.midi,
        lyric: topNote.lyric,
        isGlideEnd: true, // End of first glide (bottom1 -> top)
        isGlideStart: true, // Start of second glide (top -> bottom2)
        glideEndMidi: notes[2].midi, // End of second glide is bottom2
      );
      // Second glide: top -> bottom2 (bottom2 note should be marked as glide end)
      final lastNote = notes.last;
      notes[notes.length - 1] = ReferenceNote(
        startSec: lastNote.startSec,
        endSec: lastNote.endSec,
        midi: lastNote.midi,
        lyric: lastNote.lyric,
        isGlideEnd: true, // End of second glide (top -> bottom2)
      );
    }

    return notes;
  }

  double _computeScore() {
    final notes = _buildReferenceNotes();
    if (notes.isEmpty || _captured.isEmpty) return 0.0;
    // Filter out frames captured during lead-in period (do not score during lead-in)
    final scoredFrames = _captured
        .where((f) => AudioConstants.shouldScoreAtTime(f.time))
        .toList();
    if (scoredFrames.isEmpty) return 0.0;
    final result =
        RobustNoteScoringService().score(notes: notes, frames: scoredFrames);
    return result.overallScorePct;
  }

  Future<void> _saveAttempt(
      {double? score, Map<String, double>? subScores}) async {
    if (_attemptSaved || score == null || _startedAt == null) return;
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      subScores: subScores,
      recorderStartSec: _recorderStartSec,
      pitchDifficulty: widget.pitchDifficulty.name,
      recordingPath: _lastRecordingPath,
      contourJson: _lastContourJson,
      targetNotesJson: _buildTargetNotesJson(),
      segmentsJson: _buildSegmentsJson(),
    );
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }

  Future<void> _completeAndPop(
      double score, Map<String, double>? subScores) async {
    await _saveAttempt(score: score, subScores: subScores);
    if (!mounted) return;
    final level = pitchHighwayDifficultyLevel(widget.pitchDifficulty);
    final updated = await _levelProgress.saveAttempt(
      exerciseId: widget.exercise.id,
      level: level,
      score: score.round(),
    );
    if (score > 90 &&
        level == updated.highestUnlockedLevel &&
        level < ExerciseLevelProgress.maxLevel) {
      await _levelProgress.updateUnlockedLevel(
        exerciseId: widget.exercise.id,
        newLevel: level + 1,
      );
    }
    if (!mounted) return;

    // Get the saved attempt to navigate to review
    final savedAttempt = await _getSavedAttempt();
    if (savedAttempt != null && mounted) {
      // Navigate to review summary instead of just popping
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ExerciseReviewSummaryScreen(
            exercise: widget.exercise,
            attempt: savedAttempt,
          ),
        ),
      );
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(score);
    }
  }

  Future<ExerciseAttempt?> _getSavedAttempt() async {
    // Ensure repository is loaded
    await AttemptRepository.instance.ensureLoaded();
    // Get the most recent attempt for this exercise (should be the one we just saved)
    return AttemptRepository.instance.latestFor(widget.exercise.id);
  }

  String _formatTime(double t) {
    final totalSeconds = t.clamp(0, 24 * 60 * 60).floor();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    final notes = _buildReferenceNotes();
    // Y-axis mapping is set once from user's vocal range in initState
    // Do NOT recalculate from notes - this would cause visual jumps
    // _midiMin and _midiMax remain constant throughout the exercise
    final totalDuration = _durationSec > 0 ? _durationSec : 1.0;
    final difficultyLabel = pitchHighwayDifficultyLabel(widget.pitchDifficulty);
    return WillPopScope(
      onWillPop: _handleExit,
      child: AppBackground(
        child: SafeArea(
          bottom: false,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: isStarting || isRunning ? _stop : onStartPressed,
            child: Stack(
              children: [
                // DEBUG OVERLAY - Toggle with _showDebugOverlay flag
                if (_showDebugOverlay)
                  Positioned(
                    top: 40,
                    left: 16,
                    child: GestureDetector(
                      onLongPress: () {
                        setState(() {
                          _showDebugOverlay = false;
                        });
                      },
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Debug Overlay (long-press to hide)',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'runId: $_runId\n'
                                'phase: $_phase\n'
                                'timelineStartEpochMs: ${_timelineStartEpochMs ?? "null"}\n'
                                'tap: ${_tapEpochMs ?? "null"}\n'
                                'audioPlayCalled: ${_audioPlayCalledEpochMs ?? "null"}\n'
                                'audioPlaying: ${_audioPlayingEpochMs ?? "null"}\n'
                                'MIDI runId: $_runId\n'
                                'MIDI playing: ${_phase == StartPhase.running}\n'
                                'time: ${_time.value.toStringAsFixed(2)}s\n'
                                'now: ${DateTime.now().millisecondsSinceEpoch}\n'
                                '${_patternSpec != null && _transposedNotes.isNotEmpty ? "Pattern: ${_patternSpec!.exerciseId}\n"
                                    "  noteCount: ${_patternSpec!.noteCount}\n"
                                    "  duration: ${_patternSpec!.patternDurationSec.toStringAsFixed(2)}s\n"
                                    "  gap: ${_patternSpec!.gapBetweenPatterns.toStringAsFixed(2)}s\n"
                                    "  maxDelta: ${_patternSpec!.maxMidiDelta}\n"
                                    "  visualNotes: ${_transposedNotes.length}\n"
                                    "  MIDI range: $_midiMin - $_midiMax\n"
                                    "  totalDuration: ${_durationSec.toStringAsFixed(2)}s\n" : ""}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                // Only render pitch highway once notes are loaded to prevent showing old data
                // Use key to force remount on each run to prevent stale painter state
                if (_notesLoaded)
                  Positioned.fill(
                    key:
                        _pitchHighwayKey, // Force remount to prevent stale painter state
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        _canvasSize =
                            Size(constraints.maxWidth, constraints.maxHeight);

                        // Log repaint listenable identity and model identities
                        // CRITICAL: Use stable _time as repaint listenable (never Listenable.merge)
                        final modelHash = _time.hashCode;
                        final repaintHash =
                            _time.hashCode; // Always equals modelHash (stable)

                        // Tripwire: detect model/notifier identity changes within a run
                        if (_lastModelHash != null &&
                            _lastModelHash != modelHash &&
                            _playing) {
                          DebugLog.tripwire(LogCat.error, 'model_changed',
                              message:
                                  'modelHash CHANGED from $_lastModelHash to $modelHash runId=$_runId',
                              runId: _runId);
                        }
                        // Tripwire: repaintHash should always equal _time.hashCode and never change mid-run
                        if (_lastRepaintHash != null &&
                            _lastRepaintHash != repaintHash &&
                            _playing) {
                          DebugLog.tripwire(LogCat.error, 'repaint_changed',
                              message:
                                  'repaintHash CHANGED from $_lastRepaintHash to $repaintHash runId=$_runId (expected=$modelHash)',
                              runId: _runId);
                        }
                        // Assert: repaintHash must equal _time.hashCode
                        if (repaintHash != modelHash) {
                          DebugLog.tripwire(LogCat.error, 'repaint_mismatch',
                              message:
                                  'repaintHash ($repaintHash) != modelHash ($modelHash) runId=$_runId',
                              runId: _runId);
                        }

                        _lastModelHash = modelHash;
                        _lastRepaintHash = repaintHash;

                        return CustomPaint(
                          painter: PitchHighwayPainter(
                            notes: notes,
                            pitchTail: const [],
                            tailPoints: _tailBuffer.points,
                            time: _time,
                            pixelsPerSecond: _pixelsPerSecond,
                            liveMidi: _liveMidi,
                            pitchTailTimeOffsetSec: 0,
                            noteTimeOffsetSec: _leadInSec,
                            drawBackground: false,
                            midiMin: _midiMin,
                            midiMax: _midiMax,
                            colors: colors,
                            runId: _runId, // Pass runId to painter for logging
                            sirenPath:
                                _sirenVisualPath, // Pass visual path for Sirens
                          ),
                        );
                      },
                    ),
                  ),
                if (widget.showBackButton)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () async {
                          final shouldPop = await _handleExit();
                          if (shouldPop && mounted) {
                            Navigator.of(context).maybePop();
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child:
                              Icon(Icons.arrow_back, color: colors.textPrimary),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: widget.showBackButton ? 52 : 12,
                  left: 16,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.surface2,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: colors.borderSubtle),
                    ),
                    child: Text(
                      difficultyLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                if (isStarting)
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Preparing audio...',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                if (_scorePct != null)
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12, right: 16),
                      child: Text(
                        'Score ${_scorePct!.toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                if (!_notesLoaded && _rangeError == null)
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: colors.surface2,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            'Preparing...',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: colors.textSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_rangeError != null)
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline,
                              color: Colors.red.shade700, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            _rangeError!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.red.shade900,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          ValueListenableBuilder<double>(
                            valueListenable: _time,
                            builder: (_, v, __) => Text(
                              _formatTime(v),
                              style: TextStyle(color: colors.textSecondary),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  color: colors.surface2,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                alignment: Alignment.centerLeft,
                                child: ValueListenableBuilder<double>(
                                  valueListenable: _time,
                                  builder: (_, v, __) {
                                    final pct =
                                        (v / totalDuration).clamp(0.0, 1.0);
                                    return FractionallySizedBox(
                                      widthFactor: pct,
                                      child: Container(
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: colors.accentPurple,
                                          borderRadius:
                                              BorderRadius.circular(3),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          Text(
                            _formatTime(totalDuration),
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BreathTimerPlayer extends StatefulWidget {
  final VocalExercise exercise;

  const BreathTimerPlayer({super.key, required this.exercise});

  @override
  State<BreathTimerPlayer> createState() => _BreathTimerPlayerState();
}

class _BreathTimerPlayerState extends State<BreathTimerPlayer>
    with SingleTickerProviderStateMixin {
  final AudioSynthService _synth = AudioSynthService();
  final ProgressService _progress = ProgressService();
  Ticker? _ticker;
  Duration? _lastTick;
  bool _running = false;
  bool _preparing = false;
  int _prepRemaining = 0;
  Timer? _prepTimer;
  int _prepRunId = 0;
  double _elapsed = 0;
  double? _scorePct;
  DateTime? _startedAt;
  bool _attemptSaved = false;
  final _phases = const [
    _BreathPhase('Inhale', 4),
    _BreathPhase('Hold', 4),
    _BreathPhase('Exhale', 6),
  ];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _prepTimer?.cancel();
    _synth.stop();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_running) return;
    final dt = elapsed - (_lastTick ?? elapsed);
    _lastTick = elapsed;
    final next = _elapsed + dt.inMicroseconds / 1e6;
    final target =
        (widget.exercise.durationSeconds ?? 30).clamp(0, 30).toDouble();
    if (next >= target) {
      _elapsed = target;
      _finish();
      return;
    }
    setState(() => _elapsed = next);
  }

  Future<void> _start() async {
    if (_running || _preparing) return;
    _prepRunId += 1;
    final runId = _prepRunId;
    _beginPrepCountdown();
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted || !_preparing || runId != _prepRunId) return;
    _endPrepCountdown();
    await _playCueTone();
    _elapsed = 0;
    _scorePct = null;
    _attemptSaved = false;
    _startedAt = DateTime.now();
    _running = true;
    _lastTick = null;
    _ticker?.start();
    setState(() {});
  }

  void _stop() {
    if (!_running && !_preparing) return;
    _endPrepCountdown();
    _running = false;
    _ticker?.stop();
    _lastTick = null;
    final target =
        (widget.exercise.durationSeconds ?? 30).clamp(0, 30).toDouble();
    _scorePct = target <= 0 ? 0.0 : (_elapsed / target).clamp(0.0, 1.0) * 100.0;
    unawaited(_completeAndPop(_scorePct ?? 0, {'completion': _scorePct ?? 0}));
  }

  void _finish() {
    _running = false;
    _ticker?.stop();
    _lastTick = null;
    _scorePct = 100.0;
    unawaited(_completeAndPop(_scorePct ?? 0, {'completion': _scorePct ?? 0}));
  }

  void _beginPrepCountdown() {
    _preparing = true;
    _prepRemaining = 2;
    _prepTimer?.cancel();
    _prepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _prepRemaining = math.max(0, _prepRemaining - 1));
      if (_prepRemaining <= 0) timer.cancel();
    });
    setState(() {});
  }

  void _endPrepCountdown() {
    _preparing = false;
    _prepTimer?.cancel();
    _prepTimer = null;
    _prepRemaining = 0;
  }

  Future<void> _playCueTone() async {
    final notes = [const ReferenceNote(startSec: 0, endSec: 0.8, midi: 60)];
    final path = await _synth.renderReferenceNotes(notes);
    await _synth.playFile(path);
  }

  Future<void> _saveAttempt(
      {double? score, Map<String, double>? subScores}) async {
    if (_attemptSaved || score == null || _startedAt == null) return;
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      recorderStartSec: 0.0,
      subScores: subScores,
    );
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }

  Future<void> _completeAndPop(
      double score, Map<String, double>? subScores) async {
    await _saveAttempt(score: score, subScores: subScores);
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(score);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _phases.fold<double>(0, (a, b) => a + b.durationSec);
    var remaining = _elapsed % total;
    _BreathPhase current = _phases.first;
    for (final phase in _phases) {
      if (remaining <= phase.durationSec) {
        current = phase;
        break;
      }
      remaining -= phase.durationSec;
    }
    final phaseProgress = remaining / current.durationSec;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.exercise.description),
          const SizedBox(height: 16),
          if (_preparing) Text('Starting in $_prepRemaining...'),
          Text(current.label,
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: phaseProgress),
          if (_scorePct != null) ...[
            const SizedBox(height: 8),
            Text('Score: ${_scorePct!.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.titleMedium),
          ],
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _running ? _stop : _start,
            icon: Icon(_running ? Icons.stop : Icons.play_arrow),
            label: Text(_running ? 'Stop' : 'Start'),
          ),
        ],
      ),
    );
  }
}

class SovtTimerPlayer extends StatefulWidget {
  final VocalExercise exercise;

  const SovtTimerPlayer({super.key, required this.exercise});

  @override
  State<SovtTimerPlayer> createState() => _SovtTimerPlayerState();
}

class _SovtTimerPlayerState extends State<SovtTimerPlayer>
    with SingleTickerProviderStateMixin {
  final AudioSynthService _synth = AudioSynthService();
  final ProgressService _progress = ProgressService();
  Ticker? _ticker;
  Duration? _lastTick;
  bool _running = false;
  bool _preparing = false;
  int _prepRemaining = 0;
  Timer? _prepTimer;
  int _prepRunId = 0;
  double _elapsed = 0;
  double? _scorePct;
  DateTime? _startedAt;
  bool _attemptSaved = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _prepTimer?.cancel();
    _synth.stop();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_running) return;
    final dt = elapsed - (_lastTick ?? elapsed);
    _lastTick = elapsed;
    final next = _elapsed + dt.inMicroseconds / 1e6;
    final target =
        (widget.exercise.durationSeconds ?? 30).clamp(0, 30).toDouble();
    if (next >= target) {
      _elapsed = target;
      _finish();
      return;
    }
    setState(() => _elapsed = next);
  }

  Future<void> _start() async {
    if (_running || _preparing) return;
    _prepRunId += 1;
    final runId = _prepRunId;
    _beginPrepCountdown();
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted || !_preparing || runId != _prepRunId) return;
    _endPrepCountdown();
    await _playCueTone();
    _elapsed = 0;
    _scorePct = null;
    _attemptSaved = false;
    _startedAt = DateTime.now();
    _running = true;
    _lastTick = null;
    _ticker?.start();
    setState(() {});
  }

  void _stop() {
    if (!_running && !_preparing) return;
    _endPrepCountdown();
    _running = false;
    _ticker?.stop();
    _lastTick = null;
    final target =
        (widget.exercise.durationSeconds ?? 30).clamp(0, 30).toDouble();
    _scorePct = target <= 0 ? 0.0 : (_elapsed / target).clamp(0.0, 1.0) * 100.0;
    unawaited(_completeAndPop(_scorePct ?? 0, {'completion': _scorePct ?? 0}));
  }

  void _finish() {
    _running = false;
    _ticker?.stop();
    _lastTick = null;
    _scorePct = 100.0;
    unawaited(_completeAndPop(_scorePct ?? 0, {'completion': _scorePct ?? 0}));
  }

  void _beginPrepCountdown() {
    _preparing = true;
    _prepRemaining = 2;
    _prepTimer?.cancel();
    _prepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _prepRemaining = math.max(0, _prepRemaining - 1));
      if (_prepRemaining <= 0) timer.cancel();
    });
    setState(() {});
  }

  void _endPrepCountdown() {
    _preparing = false;
    _prepTimer?.cancel();
    _prepTimer = null;
    _prepRemaining = 0;
  }

  Future<void> _playCueTone() async {
    final notes = [const ReferenceNote(startSec: 0, endSec: 0.8, midi: 60)];
    final path = await _synth.renderReferenceNotes(notes);
    await _synth.playFile(path);
  }

  Future<void> _saveAttempt(
      {double? score, Map<String, double>? subScores}) async {
    if (_attemptSaved || score == null || _startedAt == null) return;
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      recorderStartSec: 0.0,
      subScores: subScores,
    );
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }

  Future<void> _completeAndPop(
      double score, Map<String, double>? subScores) async {
    await _saveAttempt(score: score, subScores: subScores);
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(score);
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration =
        (widget.exercise.durationSeconds ?? 30).clamp(0, 30).toDouble();
    final remaining = math.max(0, duration - _elapsed);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.exercise.description),
          const SizedBox(height: 16),
          if (_preparing) Text('Starting in $_prepRemaining...'),
          Text('${remaining.toStringAsFixed(0)}s remaining',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          if (_scorePct != null) ...[
            const SizedBox(height: 8),
            Text('Score: ${_scorePct!.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.titleMedium),
          ],
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _running ? _stop : _start,
            icon: Icon(_running ? Icons.stop : Icons.play_arrow),
            label: Text(_running ? 'Stop' : 'Start'),
          ),
        ],
      ),
    );
  }
}

// TODO: Next release - Multi-note progression, review screen, improved flow
// Current limitations: Only generates a single note, requires quitting to end, no review flow
class SustainedPitchHoldPlayer extends StatefulWidget {
  final VocalExercise exercise;

  const SustainedPitchHoldPlayer({super.key, required this.exercise});

  @override
  State<SustainedPitchHoldPlayer> createState() =>
      _SustainedPitchHoldPlayerState();
}

class _SustainedPitchHoldPlayerState extends State<SustainedPitchHoldPlayer> {
  final AudioSynthService _synth = AudioSynthService();
  final _recording = RecordingService();
  final ProgressService _progress = ProgressService();
  StreamSubscription<PitchFrame>? _sub;
  bool _listening = false;
  bool _preparing = false;
  int _prepRemaining = 0;
  Timer? _prepTimer;
  int _prepRunId = 0;
  int _targetMidi = 60;
  double? _centsError; // Nullable to match CentsMeter
  double _onPitchSec = 0;
  double _listeningSec = 0;
  double _lastTime = 0;
  final _holdGoalSec = 3.0;
  double? _confidence = 0.0;
  double? _scorePct;
  DateTime? _startedAt;
  bool _attemptSaved = false;
  double? _recorderStartSec;
  final List<PitchFrame> _captured = [];

  @override
  void dispose() {
    // ignore: avoid_print
    print('[SustainedPitchHoldPlayer] dispose - cleaning up resources');
    _sub?.cancel();
    // Properly stop and dispose the recording service
    _recording.stop().then((_) async {
      try {
        await _recording.dispose();
        // ignore: avoid_print
        print('[SustainedPitchHoldPlayer] Recording disposed');
      } catch (e) {
        // ignore: avoid_print
        print('[SustainedPitchHoldPlayer] Error disposing recording: $e');
      }
    }).catchError((e) {
      // ignore: avoid_print
      print('[SustainedPitchHoldPlayer] Error stopping recording: $e');
    });
    _prepTimer?.cancel();
    _synth.stop();
    super.dispose();
  }

  double get _targetHz => 440.0 * math.pow(2.0, (_targetMidi - 69) / 12.0);

  Future<void> _start() async {
    if (_listening || _preparing) return;
    _prepRunId += 1;
    final runId = _prepRunId;
    _beginPrepCountdown();
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted || !_preparing || runId != _prepRunId) return;
    _endPrepCountdown();
    await _playCueTone();
    _recorderStartSec = 0.0; // Free play mode, no master timeline
    await _recording.start();
    _lastTime = 0;
    _onPitchSec = 0;
    _listeningSec = 0;
    _attemptSaved = false;
    _startedAt = DateTime.now();
    _sub = _recording.liveStream.listen((frame) {
      final hz = frame.hz;
      if (hz == null || hz <= 0) {
        setState(() {
          _centsError = null;
          _confidence = 0.0;
        });
        return;
      }
      final cents = 1200 * (math.log(hz / _targetHz) / math.ln2);
      
      // Use natives service time for duration calculations to be sample-accurate
      final dt = _lastTime == 0 ? 0 : math.max(0, frame.time - _lastTime);
      _lastTime = frame.time;
      if (dt > 0) {
        _listeningSec += dt;
      }
      final voiced =
          (frame.voicedProb ?? 1.0) >= 0.6 && (frame.rms ?? 1.0) >= 0.02;
      if (voiced && cents.abs() <= 25) {
        _onPitchSec += dt;
      } else if (dt > 0.2) {
        _onPitchSec = 0;
      }
      setState(() {
        _centsError = cents;
        _confidence = frame.voicedProb ?? 0.0;
      });
      
      // Although we don't use high-def review for this exercise yet,
      // we store relative frames for uniformity.
      final pf = PitchFrame(time: frame.time, hz: hz, midi: frame.midi);
      _captured.add(pf);
    });
    _scorePct = null;
    setState(() => _listening = true);
  }

  Future<void> _stop() async {
    if (!_listening && !_preparing) return;
    _endPrepCountdown();
    await _sub?.cancel();
    _sub = null;
    // ignore: avoid_print
    print('[SustainedPitchHoldPlayer] _stop - stopping recording');
    await _recording.stop();
    // Dispose the recording service to fully release resources
    try {
      await _recording.dispose();
      // ignore: avoid_print
      print('[SustainedPitchHoldPlayer] Recording disposed');
    } catch (e) {
      // ignore: avoid_print
      print('[SustainedPitchHoldPlayer] Error disposing recording: $e');
    }
    _listening = false;
    final stability = _listeningSec > 0 ? (_onPitchSec / _listeningSec) : 0.0;
    _scorePct = (stability.clamp(0.0, 1.0) * 100.0);
    await _completeAndPop(_scorePct ?? 0, {'stability': _scorePct ?? 0});
  }

  void _beginPrepCountdown() {
    _preparing = true;
    _prepRemaining = 2;
    _prepTimer?.cancel();
    _prepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _prepRemaining = math.max(0, _prepRemaining - 1));
      if (_prepRemaining <= 0) timer.cancel();
    });
    setState(() {});
  }

  void _endPrepCountdown() {
    _preparing = false;
    _prepTimer?.cancel();
    _prepTimer = null;
    _prepRemaining = 0;
  }

  Future<void> _playCueTone() async {
    final notes = [ReferenceNote(startSec: 0, endSec: 1.2, midi: _targetMidi)];
    final path = await _synth.renderReferenceNotes(notes);
    await _synth.playFile(path);
  }

  Future<void> _saveAttempt(
      {double? score, Map<String, double>? subScores}) async {
    if (_attemptSaved || score == null || _startedAt == null) return;
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      recorderStartSec: 0.0,
      subScores: subScores,
    );
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }

  Future<void> _completeAndPop(
      double score, Map<String, double>? subScores) async {
    await _saveAttempt(score: score, subScores: subScores);
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(score);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_onPitchSec / _holdGoalSec).clamp(0.0, 1.0);
    final stability = _listeningSec > 0 ? (_onPitchSec / _listeningSec) : 0.0;
    final targetNoteName = PitchMath.midiToName(_targetMidi);
    final inTune = _centsError != null && _centsError!.abs() <= 10;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.exercise.description),
          const SizedBox(height: 12),
          if (_preparing) Text('Starting in $_prepRemaining...'),
          Text(
            'Target: $targetNoteName',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          Slider(
            value: _targetMidi.toDouble(),
            min: 48,
            max: 72,
            divisions: 24,
            label: targetNoteName,
            onChanged: (v) => setState(() => _targetMidi = v.round()),
          ),
          const SizedBox(height: 24),
          CentsMeter(
            cents: _centsError,
            confidence: _confidence ?? 0.0,
          ),
          const SizedBox(height: 12),
          Text(
            inTune
                ? 'In tune'
                : (_centsError == null ? 'No pitch detected' : 'Adjust pitch'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: inTune ? Colors.green : Colors.black54,
                ),
          ),
          const SizedBox(height: 24),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          Text('Stability: ${(stability * 100).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodyMedium),
          if (_scorePct != null) ...[
            const SizedBox(height: 8),
            Text('Score: ${_scorePct!.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.titleMedium),
          ],
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _listening ? _stop : _start,
            icon: Icon(_listening ? Icons.stop : Icons.hearing),
            label: Text(_listening ? 'Stop' : 'Start'),
          ),
        ],
      ),
    );
  }
}

// TODO: Next release - Expand interval logic, multiple interval types, proper preview coverage
// Current limitations: Only generates a minor 2nd, no clean way to end exercise except quitting
class PitchMatchListeningPlayer extends StatefulWidget {
  final VocalExercise exercise;

  const PitchMatchListeningPlayer({super.key, required this.exercise});

  @override
  State<PitchMatchListeningPlayer> createState() =>
      _PitchMatchListeningPlayerState();
}

class _PitchMatchListeningPlayerState extends State<PitchMatchListeningPlayer> {
  final _synth = AudioSynthService();
  final _recording = RecordingService();
  final ProgressService _progress = ProgressService();
  StreamSubscription<PitchFrame>? _sub;
  bool _listening = false;
  bool _preparing = false;
  int _prepRemaining = 0;
  Timer? _prepTimer;
  int _prepRunId = 0;
  int _targetMidi = 60;
  double _centsError = 0;
  double? _scorePct;
  final List<double> _absErrors = [];
  DateTime? _startedAt;
  bool _attemptSaved = false;
  double? _recorderStartSec;
  final List<PitchFrame> _captured = [];

  // Interval Training: list of intervals in semitones
  static const List<int> _intervals = [
    1,
    2,
    3,
    4,
    5,
    7,
    8,
    9,
    10,
    11,
    12
  ]; // m2, M2, m3, M3, P4, P5, m6, M6, m7, M7, P8
  static const List<String> _intervalNames = [
    'm2',
    'M2',
    'm3',
    'M3',
    'P4',
    'P5',
    'm6',
    'M6',
    'm7',
    'M7',
    'P8'
  ];
  int _currentIntervalIndex = 0;
  int _rootMidi = 60; // C4

  @override
  void dispose() {
    // ignore: avoid_print
    print('[PitchMatchListeningPlayer] dispose - cleaning up resources');
    _sub?.cancel();
    // Properly stop and dispose the recording service
    _recording.stop().then((_) async {
      try {
        await _recording.dispose();
        // ignore: avoid_print
        print('[PitchMatchListeningPlayer] Recording disposed');
      } catch (e) {
        // ignore: avoid_print
        print('[PitchMatchListeningPlayer] Error disposing recording: $e');
      }
    }).catchError((e) {
      // ignore: avoid_print
      print('[PitchMatchListeningPlayer] Error stopping recording: $e');
    });
    _prepTimer?.cancel();
    _synth.stop();
    super.dispose();
  }

  double get _targetHz => 440.0 * math.pow(2.0, (_targetMidi - 69) / 12.0);

  Future<void> _playTone() async {
    if (widget.exercise.id == 'interval_training') {
      // For Interval Training: play root, then interval
      final intervalSemitones = _intervals[_currentIntervalIndex];
      final intervalMidi = _rootMidi + intervalSemitones;
      final notes = [
        ReferenceNote(startSec: 0, endSec: 1.0, midi: _rootMidi),
        ReferenceNote(startSec: 1.2, endSec: 2.2, midi: intervalMidi),
      ];
      final path = await _synth.renderReferenceNotes(notes);
      await _synth.playFile(path);
      // Update target to the interval note
      setState(() => _targetMidi = intervalMidi);
    } else {
      // For other exercises (call-and-response): single tone
      final notes = [
        ReferenceNote(startSec: 0, endSec: 1.2, midi: _targetMidi),
      ];
      final path = await _synth.renderReferenceNotes(notes);
      await _synth.playFile(path);
    }
  }

  void _nextInterval() {
    if (widget.exercise.id == 'interval_training') {
      setState(() {
        _currentIntervalIndex = (_currentIntervalIndex + 1) % _intervals.length;
        final intervalSemitones = _intervals[_currentIntervalIndex];
        _targetMidi = _rootMidi + intervalSemitones;
      });
    }
  }

  Future<void> _start() async {
    if (_listening || _preparing) return;
    _prepRunId += 1;
    final runId = _prepRunId;
    _beginPrepCountdown();
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted || !_preparing || runId != _prepRunId) return;
    _endPrepCountdown();
    await _playTone();
    _recorderStartSec = 0.0; // Always start at beginning for these simpler exercises
    await _recording.start();
    _absErrors.clear();
    _attemptSaved = false;
    _startedAt = DateTime.now();
    _sub = _recording.liveStream.listen((frame) {
      final hz = frame.hz;
      if (hz == null || hz <= 0) return;
      final cents = 1200 * (math.log(hz / _targetHz) / math.ln2);
      _absErrors.add(cents.abs());
      setState(() => _centsError = cents);
      
      // Store relative frames for uniformity
      _captured.add(PitchFrame(time: frame.time, hz: hz, midi: frame.midi));
    });
    _scorePct = null;
    setState(() => _listening = true);
  }

  Future<void> _stop() async {
    if (!_listening && !_preparing) return;
    _endPrepCountdown();
    await _sub?.cancel();
    _sub = null;
    // ignore: avoid_print
    print('[PitchMatchListeningPlayer] _stop - stopping recording');
    await _recording.stop();
    // Dispose the recording service to fully release resources
    try {
      await _recording.dispose();
      // ignore: avoid_print
      print('[PitchMatchListeningPlayer] Recording disposed');
    } catch (e) {
      // ignore: avoid_print
      print('[PitchMatchListeningPlayer] Error disposing recording: $e');
    }
    _listening = false;
    if (_absErrors.isEmpty) {
      _scorePct = 0.0;
    } else {
      final mean = _absErrors.reduce((a, b) => a + b) / _absErrors.length;
      _scorePct = (1.0 - math.min(mean / 100.0, 1.0)) * 100.0;
    }
    await _completeAndPop(_scorePct ?? 0, {'intonation': _scorePct ?? 0});
  }

  void _beginPrepCountdown() {
    _preparing = true;
    _prepRemaining = 2;
    _prepTimer?.cancel();
    _prepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _prepRemaining = math.max(0, _prepRemaining - 1));
      if (_prepRemaining <= 0) timer.cancel();
    });
    setState(() {});
  }

  void _endPrepCountdown() {
    _preparing = false;
    _prepTimer?.cancel();
    _prepTimer = null;
    _prepRemaining = 0;
  }

  Future<void> _saveAttempt(
      {double? score, Map<String, double>? subScores}) async {
    if (_attemptSaved || score == null || _startedAt == null) return;
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      recorderStartSec: 0.0,
      subScores: subScores,
    );
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }

  Future<void> _completeAndPop(
      double score, Map<String, double>? subScores) async {
    await _saveAttempt(score: score, subScores: subScores);
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(score);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIntervalTraining = widget.exercise.id == 'interval_training';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.exercise.description),
          const SizedBox(height: 12),
          if (_preparing) Text('Starting in $_prepRemaining...'),
          if (isIntervalTraining) ...[
            Text('Interval: ${_intervalNames[_currentIntervalIndex]}',
                style: Theme.of(context).textTheme.titleMedium),
            Text('Root: C4 (MIDI $_rootMidi) → Target: MIDI $_targetMidi',
                style: Theme.of(context).textTheme.bodyMedium),
          ] else ...[
            Text('Target: MIDI $_targetMidi',
                style: Theme.of(context).textTheme.titleMedium),
            Slider(
              value: _targetMidi.toDouble(),
              min: 48,
              max: 72,
              divisions: 24,
              label: _targetMidi.toString(),
              onChanged: (v) => setState(() => _targetMidi = v.round()),
            ),
          ],
          const SizedBox(height: 8),
          Text('${_centsError.toStringAsFixed(1)} cents',
              style: Theme.of(context).textTheme.headlineMedium),
          if (_scorePct != null) ...[
            const SizedBox(height: 8),
            Text('Score: ${_scorePct!.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.titleMedium),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _listening ? _stop : _start,
                  icon: Icon(_listening ? Icons.stop : Icons.hearing),
                  label: Text(_listening ? 'Stop' : 'Start'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _playTone,
                  icon: const Icon(Icons.volume_up),
                  label: const Text('Replay'),
                ),
              ),
            ],
          ),
          if (isIntervalTraining && !_listening) ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _nextInterval,
              icon: const Icon(Icons.skip_next),
              label: const Text('Next Interval'),
            ),
          ],
        ],
      ),
    );
  }
}

class ArticulationRhythmPlayer extends StatefulWidget {
  final VocalExercise exercise;

  const ArticulationRhythmPlayer({super.key, required this.exercise});

  @override
  State<ArticulationRhythmPlayer> createState() =>
      _ArticulationRhythmPlayerState();
}

class _ArticulationRhythmPlayerState extends State<ArticulationRhythmPlayer>
    with SingleTickerProviderStateMixin {
  final AudioSynthService _synth = AudioSynthService();
  final ProgressService _progress = ProgressService();
  Ticker? _ticker;
  Duration? _lastTick;
  bool _running = false;
  bool _preparing = false;
  int _prepRemaining = 0;
  Timer? _prepTimer;
  int _prepRunId = 0;
  double _elapsed = 0;
  double? _scorePct;
  final _tempoBpm = 90.0;
  DateTime? _startedAt;
  bool _attemptSaved = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _prepTimer?.cancel();
    _synth.stop();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_running) return;
    final dt = elapsed - (_lastTick ?? elapsed);
    _lastTick = elapsed;
    final next = _elapsed + dt.inMicroseconds / 1e6;
    final target =
        (widget.exercise.durationSeconds ?? 30).clamp(0, 30).toDouble();
    if (next >= target) {
      _elapsed = target;
      _finish();
      return;
    }
    setState(() => _elapsed = next);
  }

  Future<void> _start() async {
    if (_running || _preparing) return;
    _prepRunId += 1;
    final runId = _prepRunId;
    _beginPrepCountdown();
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted || !_preparing || runId != _prepRunId) return;
    _endPrepCountdown();
    await _playCueTone();
    _elapsed = 0;
    _scorePct = null;
    _attemptSaved = false;
    _startedAt = DateTime.now();
    _running = true;
    _lastTick = null;
    _ticker?.start();
    setState(() {});
  }

  void _stop() {
    if (!_running && !_preparing) return;
    _endPrepCountdown();
    _running = false;
    _ticker?.stop();
    _lastTick = null;
    final target =
        (widget.exercise.durationSeconds ?? 30).clamp(0, 30).toDouble();
    _scorePct = target <= 0 ? 0.0 : (_elapsed / target).clamp(0.0, 1.0) * 100.0;
    unawaited(_completeAndPop(_scorePct ?? 0, {'timing': _scorePct ?? 0}));
  }

  void _finish() {
    _running = false;
    _ticker?.stop();
    _lastTick = null;
    _scorePct = 100.0;
    unawaited(_completeAndPop(_scorePct ?? 0, {'timing': _scorePct ?? 0}));
  }

  void _beginPrepCountdown() {
    _preparing = true;
    _prepRemaining = 2;
    _prepTimer?.cancel();
    _prepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _prepRemaining = math.max(0, _prepRemaining - 1));
      if (_prepRemaining <= 0) timer.cancel();
    });
    setState(() {});
  }

  void _endPrepCountdown() {
    _preparing = false;
    _prepTimer?.cancel();
    _prepTimer = null;
    _prepRemaining = 0;
  }

  Future<void> _playCueTone() async {
    final notes = [const ReferenceNote(startSec: 0, endSec: 0.8, midi: 60)];
    final path = await _synth.renderReferenceNotes(notes);
    await _synth.playFile(path);
  }

  Future<void> _saveAttempt(
      {double? score, Map<String, double>? subScores}) async {
    if (_attemptSaved || score == null || _startedAt == null) return;
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      recorderStartSec: 0.0,
      subScores: subScores,
    );
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }

  Future<void> _completeAndPop(
      double score, Map<String, double>? subScores) async {
    await _saveAttempt(score: score, subScores: subScores);
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(score);
    }
  }

  List<String> get _syllables {
    if (widget.exercise.id == 'tongue_twisters') {
      return const ['Red', 'leather', 'yellow', 'leather'];
    }
    if (widget.exercise.id == 'consonant_isolation') {
      return const ['T', 'K', 'D', 'T', 'K', 'D'];
    }
    return const ['Ta', 'Ta', 'Ta', 'Ta'];
  }

  @override
  Widget build(BuildContext context) {
    final beatSec = 60 / _tempoBpm;
    final beatIndex = ((_elapsed / beatSec).floor()) % _syllables.length;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.exercise.description),
          const SizedBox(height: 16),
          if (_preparing) Text('Starting in $_prepRemaining...'),
          Text('Tempo: ${_tempoBpm.toStringAsFixed(0)} bpm'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: List.generate(_syllables.length, (i) {
              final active = i == beatIndex && _running;
              return Chip(
                label: Text(_syllables[i]),
                backgroundColor:
                    active ? Colors.blue.shade200 : Colors.grey.shade200,
              );
            }),
          ),
          const SizedBox(height: 16),
          if (_scorePct != null)
            Text('Score: ${_scorePct!.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _running ? _stop : _start,
            icon: Icon(_running ? Icons.stop : Icons.play_arrow),
            label: Text(_running ? 'Stop' : 'Start'),
          ),
        ],
      ),
    );
  }
}

class DynamicsRampPlayer extends StatefulWidget {
  final VocalExercise exercise;

  const DynamicsRampPlayer({super.key, required this.exercise});

  @override
  State<DynamicsRampPlayer> createState() => _DynamicsRampPlayerState();
}

class _DynamicsRampPlayerState extends State<DynamicsRampPlayer>
    with SingleTickerProviderStateMixin {
  final AudioSynthService _synth = AudioSynthService();
  final _recording = RecordingService();
  final ProgressService _progress = ProgressService();
  StreamSubscription<PitchFrame>? _sub;
  Ticker? _ticker;
  Duration? _lastTick;
  bool _running = false;
  bool _preparing = false;
  int _prepRemaining = 0;
  Timer? _prepTimer;
  int _prepRunId = 0;
  double _elapsed = 0;
  double _rms = 0;
  double? _scorePct;
  final List<double> _sampleTimes = [];
  final List<double> _sampleRms = [];
  DateTime? _startedAt;
  bool _attemptSaved = false;
  double? _recorderStartSec;
  final List<PitchFrame> _captured = [];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    // ignore: avoid_print
    print('[DynamicsRampPlayer] dispose - cleaning up resources');
    _ticker?.dispose();
    _sub?.cancel();
    // Properly stop and dispose the recording service
    _recording.stop().then((_) async {
      try {
        await _recording.dispose();
        // ignore: avoid_print
        print('[DynamicsRampPlayer] Recording disposed');
      } catch (e) {
        // ignore: avoid_print
        print('[DynamicsRampPlayer] Error disposing recording: $e');
      }
    }).catchError((e) {
      // ignore: avoid_print
      print('[DynamicsRampPlayer] Error stopping recording: $e');
    });
    _prepTimer?.cancel();
    _synth.stop();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_running) return;
    final dt = elapsed - (_lastTick ?? elapsed);
    _lastTick = elapsed;
    final next = _elapsed + dt.inMicroseconds / 1e6;
    final target =
        (widget.exercise.durationSeconds ?? 30).clamp(0, 30).toDouble();
    if (next >= target) {
      _elapsed = target;
      _finish();
      return;
    }
    setState(() => _elapsed = next);
  }

  Future<void> _toggle() async {
    if (_running) {
      _stop();
      return;
    }
    if (_preparing) return;
    _prepRunId += 1;
    final runId = _prepRunId;
    _beginPrepCountdown();
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted || !_preparing || runId != _prepRunId) return;
    _endPrepCountdown();
    await _playCueTone();
    _recorderStartSec = _elapsed;
    await _recording.start();
    _sampleTimes.clear();
    _sampleRms.clear();
    _attemptSaved = false;
    _startedAt = DateTime.now();
    _sub = _recording.liveStream.listen((frame) {
      final rms = frame.rms ?? 0.0;
      // frame.time is natively relative to start of audio file
      _sampleTimes.add(frame.time); 
      _sampleRms.add(rms);
      setState(() => _rms = rms);
      
      // Storing relative frames for consistency
      _captured.add(PitchFrame(time: frame.time, hz: frame.hz, midi: frame.midi, rms: rms));
    });
    setState(() {
      _running = true;
      _elapsed = 0;
      _scorePct = null;
      _lastTick = null;
      _ticker?.start();
    });
  }

  void _stop() {
    if (!_running && !_preparing) return;
    _endPrepCountdown();
    _ticker?.stop();
    _lastTick = null;
    _running = false;
    _scorePct = _computeScore();
    _sub?.cancel();
    // Properly stop and dispose the recording service
    _recording.stop().then((_) async {
      try {
        await _recording.dispose();
        // ignore: avoid_print
        print('[DynamicsRampPlayer] Recording disposed in _stop');
      } catch (e) {
        // ignore: avoid_print
        print('[DynamicsRampPlayer] Error disposing recording: $e');
      }
    }).catchError((e) {
      // ignore: avoid_print
      print('[DynamicsRampPlayer] Error stopping recording: $e');
    });
    unawaited(_completeAndPop(_scorePct ?? 0, {'dynamics': _scorePct ?? 0}));
  }

  void _finish() {
    _running = false;
    _ticker?.stop();
    _lastTick = null;
    _scorePct = _computeScore();
    _sub?.cancel();
    // Properly stop and dispose the recording service
    _recording.stop().then((_) async {
      try {
        await _recording.dispose();
        // ignore: avoid_print
        print('[DynamicsRampPlayer] Recording disposed in _finish');
      } catch (e) {
        // ignore: avoid_print
        print('[DynamicsRampPlayer] Error disposing recording: $e');
      }
    }).catchError((e) {
      // ignore: avoid_print
      print('[DynamicsRampPlayer] Error stopping recording: $e');
    });
    unawaited(_completeAndPop(_scorePct ?? 0, {'dynamics': _scorePct ?? 0}));
  }

  void _beginPrepCountdown() {
    _preparing = true;
    _prepRemaining = 2;
    _prepTimer?.cancel();
    _prepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _prepRemaining = math.max(0, _prepRemaining - 1));
      if (_prepRemaining <= 0) timer.cancel();
    });
    setState(() {});
  }

  void _endPrepCountdown() {
    _preparing = false;
    _prepTimer?.cancel();
    _prepTimer = null;
    _prepRemaining = 0;
  }

  Future<void> _playCueTone() async {
    final notes = [const ReferenceNote(startSec: 0, endSec: 0.8, midi: 60)];
    final path = await _synth.renderReferenceNotes(notes);
    await _synth.playFile(path);
  }

  double _computeScore() {
    if (_sampleTimes.isEmpty || _sampleRms.isEmpty) return 0.0;
    final duration =
        (widget.exercise.durationSeconds ?? 30).clamp(0, 30).toDouble();
    double sumDiff = 0.0;
    for (var i = 0; i < _sampleTimes.length; i++) {
      final progress = (_sampleTimes[i] / duration).clamp(0.0, 1.0);
      final target =
          progress <= 0.5 ? (progress * 2) : (1 - (progress - 0.5) * 2);
      final diff = (target - _sampleRms[i]).abs();
      sumDiff += diff;
    }
    final meanDiff = sumDiff / _sampleTimes.length;
    return (1.0 - meanDiff.clamp(0.0, 1.0)) * 100.0;
  }

  Future<void> _saveAttempt(
      {double? score, Map<String, double>? subScores}) async {
    if (_attemptSaved || score == null || _startedAt == null) return;
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      recorderStartSec: 0.0,
      subScores: subScores,
    );
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }

  Future<void> _completeAndPop(
      double score, Map<String, double>? subScores) async {
    await _saveAttempt(score: score, subScores: subScores);
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(score);
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration =
        (widget.exercise.durationSeconds ?? 30).clamp(0, 30).toDouble();
    final progress = (_elapsed / duration).clamp(0.0, 1.0);
    final ramp = progress <= 0.5 ? (progress * 2) : (1 - (progress - 0.5) * 2);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.exercise.description),
          const SizedBox(height: 16),
          if (_preparing) Text('Starting in $_prepRemaining...'),
          Text('Target ramp'),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: ramp),
          const SizedBox(height: 16),
          Text('Current loudness'),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: _rms.clamp(0.0, 1.0)),
          if (_scorePct != null) ...[
            const SizedBox(height: 12),
            Text('Score: ${_scorePct!.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.titleMedium),
          ],
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _toggle,
            icon: Icon(_running ? Icons.stop : Icons.play_arrow),
            label: Text(_running ? 'Stop' : 'Start'),
          ),
        ],
      ),
    );
  }
}

class CooldownRecoveryPlayer extends StatefulWidget {
  final VocalExercise exercise;

  const CooldownRecoveryPlayer({super.key, required this.exercise});

  @override
  State<CooldownRecoveryPlayer> createState() => _CooldownRecoveryPlayerState();
}

class _CooldownRecoveryPlayerState extends State<CooldownRecoveryPlayer>
    with SingleTickerProviderStateMixin {
  final AudioSynthService _synth = AudioSynthService();
  final ProgressService _progress = ProgressService();
  Ticker? _ticker;
  Duration? _lastTick;
  bool _running = false;
  bool _preparing = false;
  int _prepRemaining = 0;
  Timer? _prepTimer;
  int _prepRunId = 0;
  double _elapsed = 0;
  double? _scorePct;
  DateTime? _startedAt;
  bool _attemptSaved = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _prepTimer?.cancel();
    _synth.stop();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_running) return;
    final dt = elapsed - (_lastTick ?? elapsed);
    _lastTick = elapsed;
    final next = _elapsed + dt.inMicroseconds / 1e6;
    final target = (widget.exercise.durationSeconds ?? 90).toDouble();
    if (next >= target) {
      _elapsed = target;
      _finish();
      return;
    }
    setState(() => _elapsed = next);
  }

  Future<void> _start() async {
    if (_running || _preparing) return;
    _prepRunId += 1;
    final runId = _prepRunId;
    _beginPrepCountdown();
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted || !_preparing || runId != _prepRunId) return;
    _endPrepCountdown();
    await _playCueTone();
    _elapsed = 0;
    _scorePct = null;
    _attemptSaved = false;
    _startedAt = DateTime.now();
    _running = true;
    _lastTick = null;
    _ticker?.start();
    setState(() {});
  }

  void _stop() {
    if (!_running && !_preparing) return;
    _endPrepCountdown();
    _running = false;
    _ticker?.stop();
    _lastTick = null;
    final target = (widget.exercise.durationSeconds ?? 90).toDouble();
    _scorePct = target <= 0 ? 0.0 : (_elapsed / target).clamp(0.0, 1.0) * 100.0;
    unawaited(_completeAndPop(_scorePct ?? 0, {'completion': _scorePct ?? 0}));
  }

  void _finish() {
    _running = false;
    _ticker?.stop();
    _lastTick = null;
    _scorePct = 100.0;
    unawaited(_completeAndPop(_scorePct ?? 0, {'completion': _scorePct ?? 0}));
  }

  void _beginPrepCountdown() {
    _preparing = true;
    _prepRemaining = 2;
    _prepTimer?.cancel();
    _prepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _prepRemaining = math.max(0, _prepRemaining - 1));
      if (_prepRemaining <= 0) timer.cancel();
    });
    setState(() {});
  }

  void _endPrepCountdown() {
    _preparing = false;
    _prepTimer?.cancel();
    _prepTimer = null;
    _prepRemaining = 0;
  }

  Future<void> _playCueTone() async {
    final notes = [const ReferenceNote(startSec: 0, endSec: 0.8, midi: 60)];
    final path = await _synth.renderReferenceNotes(notes);
    await _synth.playFile(path);
  }

  Future<void> _saveAttempt(
      {double? score, Map<String, double>? subScores}) async {
    if (_attemptSaved || score == null || _startedAt == null) return;
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      recorderStartSec: 0.0,
      subScores: subScores,
    );
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }

  Future<void> _completeAndPop(
      double score, Map<String, double>? subScores) async {
    await _saveAttempt(score: score, subScores: subScores);
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(score);
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.exercise.durationSeconds ?? 90;
    final remaining = math.max(0, duration - _elapsed);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.exercise.description),
          const SizedBox(height: 16),
          if (_preparing) Text('Starting in $_prepRemaining...'),
          Text('${remaining.toStringAsFixed(0)}s remaining',
              style: Theme.of(context).textTheme.headlineMedium),
          if (_scorePct != null) ...[
            const SizedBox(height: 8),
            Text('Score: ${_scorePct!.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.titleMedium),
          ],
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _running ? _stop : _start,
            icon: Icon(_running ? Icons.stop : Icons.play_arrow),
            label: Text(_running ? 'Stop' : 'Start'),
          ),
        ],
      ),
    );
  }
}

class _BreathPhase {
  final String label;
  final double durationSec;

  const _BreathPhase(this.label, this.durationSec);
}
