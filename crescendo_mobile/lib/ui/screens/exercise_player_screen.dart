import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';
import '../../models/exercise_plan.dart';
import '../../core/app_config.dart'; // Import AppConfig

import '../../models/pitch_frame.dart';

import '../../models/reference_note.dart';
import '../../models/siren_path.dart';
import '../../models/siren_exercise_result.dart';
import '../../models/vocal_exercise.dart';
import '../../models/last_take.dart';
import '../../models/exercise_level_progress.dart';
import '../../models/breathing_phase.dart';
import '../../design/app_text.dart';
import '../../services/audio_synth_service.dart';
import '../../services/last_take_store.dart';
import '../../services/progress_service.dart';
import '../../services/recording_service.dart';
import '../../services/robust_note_scoring_service.dart';
import '../../services/exercise_level_progress_repository.dart';
import '../../services/transposed_exercise_builder.dart';
import '../../services/vocal_range_service.dart';
import '../../services/exercise_cache_service.dart';
import '../../controllers/breathing_controller.dart';
import '../widgets/breathing_animation_widget.dart';
import '../../services/reference_audio_generator.dart';
import '../../services/audio_clock.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../services/attempt_repository.dart';
import '../../models/exercise_attempt.dart';
import '../../models/last_take_draft.dart';
import 'exercise_review_summary_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/pitch_highway_painter.dart';
import '../../widgets/ballad_scaffold.dart';
import '../../widgets/ballad_buttons.dart';
import '../../theme/ballad_theme.dart';
import '../../utils/daily_completion_utils.dart';
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
import '../../services/exercise_audio_controller.dart';
import '../../models/pattern_spec.dart';
import 'pitch_matching_screen.dart';
import 'sustained_hold_screen.dart';

/// Buffer size for recording service.
/// 1024 samples (~23ms at 44.1kHz) is needed for reliable low-frequency pitch detection.
const int _kBufferSize = 1024;

/// [ISO] Audio isolation modes for debugging Android audio focus issues
enum AudioIsolationMode { both, recordOnly, playOnly }
// const AudioIsolationMode kAudioIsolationMode = AudioIsolationMode.both;
const AudioIsolationMode kAudioIsolationMode = AudioIsolationMode.both;

const bool kAudioDebug = false; // Set to true to enable audio focus debug logging

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


  const ExercisePlayerScreen({
    super.key,
    required this.exercise,
  });

  @override
  Widget build(BuildContext context) {
    final isPitchHighway = exercise.type == ExerciseType.pitchHighway;
    final Widget body = switch (exercise.type) {
      ExerciseType.pitchHighway => const Center(child: Text("Use PitchHighwayScreen instead")),
      ExerciseType.breathTimer => BreathTimerPlayer(exercise: exercise),
      ExerciseType.sovtTimer => SovtTimerPlayer(exercise: exercise),
      ExerciseType.sustainedPitchHold =>
        SustainedHoldScreen(exercise: exercise),
      ExerciseType.pitchMatchListening =>
        PitchMatchingScreen(exercise: exercise),
      ExerciseType.articulationRhythm =>
        ArticulationRhythmPlayer(exercise: exercise),
      ExerciseType.dynamicsRamp => DynamicsRampPlayer(exercise: exercise),
      ExerciseType.cooldownRecovery =>
        CooldownRecoveryPlayer(exercise: exercise),
    };
    
    // For V0/Ballad, use the cosmic scaffold
    if (AppConfig.isV0) {
      return BalladScaffold(
        title: exercise.name,
        child: body,
      );
    }

    return Scaffold(
      appBar: (isPitchHighway)
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

class BreathTimerPlayer extends StatefulWidget {
  final VocalExercise exercise;

  const BreathTimerPlayer({super.key, required this.exercise});

  @override
  State<BreathTimerPlayer> createState() => _BreathTimerPlayerState();
}

class _BreathTimerPlayerState extends State<BreathTimerPlayer>
    with SingleTickerProviderStateMixin {
  final ProgressService _progress = ProgressService();
  BreathingController? _breathingController;
  DateTime? _startedAt;
  bool _attemptSaved = false;
  bool _isStarted = false;
  Timer? _totalCountdownTimer;

  @override
  void initState() {
    super.initState();
    _initializeController();
    // Auto-start breathing animation after a brief delay
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _start();
      }
    });
  }

  void _initializeController() {
    final phases = widget.exercise.breathingPhases;
    if (phases == null || phases.isEmpty) {
      // Fallback to default Appoggio pattern if no phases defined
      _breathingController = BreathingController(
        phases: BreathingPatterns.appoggio,
        vsync: this,
        repeatCount: widget.exercise.breathingRepeatCount ?? 0,
        onComplete: _onBreathingComplete,
      );
    } else {
      _breathingController = BreathingController(
        phases: phases,
        vsync: this,
        repeatCount: widget.exercise.breathingRepeatCount ?? 0,
        onComplete: _onBreathingComplete,
      );
    }
  }

  void _onBreathingComplete() {
    // Save attempt with 100% completion (session ended normally → counts for daily effort)
    _saveAttempt(score: 100.0, subScores: {'completion': 100.0}, sessionEndedNormally: true);
    
    // Pop with score
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(100.0);
    }
  }

  @override
  void dispose() {
    _totalCountdownTimer?.cancel();
    _breathingController?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_isStarted) return;
    
    setState(() {
      _isStarted = true;
    });
    
    _breathingController?.start();
    
    // Wait for pre-roll to complete (3 seconds) before starting total countdown
    await Future.delayed(const Duration(seconds: 3));
    
    if (!mounted || !_isStarted) return;
    
    // Now start the actual exercise timer
    setState(() {
      _startedAt = DateTime.now();
    });

    // Start periodic timer for smooth progress bar updates (20 FPS)
    _totalCountdownTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted || !_isStarted) {
        timer.cancel();
        return;
      }
      
      // Check if total duration has been reached
      final targetDuration = widget.exercise.durationSeconds ?? 30;
      final elapsed = _startedAt != null 
          ? DateTime.now().difference(_startedAt!).inSeconds 
          : 0;
      
      if (elapsed >= targetDuration) {
        timer.cancel();
        _totalCountdownTimer = null;
        _breathingController?.stop();
        _onBreathingComplete();
        return;
      }
      
      setState(() {
        // Trigger rebuild for smooth progress bar animation
      });
    });
  }

  void _stop() {
    if (!_isStarted) return;
    
    _totalCountdownTimer?.cancel();
    _breathingController?.stop();
    
    // Calculate completion percentage based on elapsed time
    final targetDuration = widget.exercise.durationSeconds ?? 30;
    final elapsed = _startedAt != null 
        ? DateTime.now().difference(_startedAt!).inSeconds 
        : 0;
    final completionPct = (elapsed / targetDuration * 100).clamp(0.0, 100.0);
    
    _saveAttempt(score: completionPct, subScores: {'completion': completionPct}, sessionEndedNormally: false);
    
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(completionPct);
    }
  }

  Future<void> _saveAttempt({
    required double score,
    required Map<String, double> subScores,
    bool sessionEndedNormally = false,
  }) async {
    if (_attemptSaved || _startedAt == null) return;
    
    final targetDuration = widget.exercise.durationSeconds ?? 30;
    final elapsed = DateTime.now().difference(_startedAt!).inSeconds;
    final completionPercent = (elapsed / targetDuration).clamp(0.0, 1.0);
    
    // Countdown: only counts for daily effort if session ended normally AND reached end
    final countsForDaily = DailyCompletionUtils.countsForDailyEffortCountdown(
      sessionEndedNormally: sessionEndedNormally,
      completionPercent: completionPercent,
      elapsedSec: elapsed,
      requiredSec: targetDuration,
    );
    
    final dateKey = DailyCompletionUtils.generateDateKey(_startedAt!);
    
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      recorderStartSec: 0.0,
      subScores: subScores,
      dateKey: dateKey,
      countsForDailyEffort: countsForDaily,
      completionPercent: completionPercent,
    );
    
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }


  @override
  Widget build(BuildContext context) {
    final controller = _breathingController;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Calculate total elapsed time for smooth progress bar
    final totalElapsed = _startedAt != null && _isStarted
        ? DateTime.now().difference(_startedAt!).inMilliseconds / 1000.0
        : 0.0;
    final targetDuration = (widget.exercise.durationSeconds ?? 30).toDouble();
    final progress = (totalElapsed / targetDuration).clamp(0.0, 1.0);

    return Stack(
      children: [
        // Top section: Phase Label only
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ValueListenableBuilder<String>(
                valueListenable: controller.currentPhaseName,
                builder: (context, phaseName, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: controller.isPreRoll,
                    builder: (context, isPreRoll, _) {
                      return ValueListenableBuilder<int>(
                        valueListenable: controller.countdown,
                        builder: (context, count, _) {
                          // During pre-roll: show countdown number
                          if (isPreRoll) {
                            return Text(
                              count.toString(),
                              textAlign: TextAlign.center,
                              style: AppText.phaseLabel.copyWith(color: Colors.white),
                            );
                          }
                          
                          // During exercise: show phase name
                          return Text(
                            phaseName,
                            textAlign: TextAlign.center,
                            style: AppText.phaseLabel.copyWith(color: Colors.white),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),

        // Middle section: Breathing circle at 30% of screen height
        Align(
          alignment: const Alignment(0, -0.4), // ~30% from top
          child: BreathingAnimationWidget(
            controller: controller,
            baseSize: 200,
            primaryColor: const Color(0xFF895BF2),
            secondaryColor: const Color(0xFF895BF2),
            showPhaseLabel: false, // Don't show label below circle
          ),
        ),

        // Bottom section: Progress bar
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    _formatTime(totalElapsed),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontFamily: 'Manrope',
                      fontSize: 14,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: progress,
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: const Color(0xFF895BF2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    _formatTime(targetDuration),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontFamily: 'Manrope',
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatTime(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '${mins}:${secs.toString().padLeft(2, '0')}';
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
    unawaited(_completeAndPop(_scorePct ?? 0, {'completion': _scorePct ?? 0}, sessionEndedNormally: false));
  }

  void _finish() {
    _running = false;
    _ticker?.stop();
    _lastTick = null;
    _scorePct = 100.0;
    unawaited(_completeAndPop(_scorePct ?? 0, {'completion': _scorePct ?? 0}, sessionEndedNormally: true));
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
      {double? score, Map<String, double>? subScores, bool sessionEndedNormally = false}) async {
    if (_attemptSaved || score == null || _startedAt == null) return;
    final targetSec = (widget.exercise.durationSeconds ?? 30).clamp(1, 999);
    final elapsedSec = _elapsed.round();
    final completionPercent = (elapsedSec / targetSec).clamp(0.0, 1.0);
    final countsForDaily = DailyCompletionUtils.countsForDailyEffortCountdown(
      sessionEndedNormally: sessionEndedNormally,
      completionPercent: completionPercent,
      elapsedSec: elapsedSec,
      requiredSec: targetSec,
    );
    final dateKey = DailyCompletionUtils.generateDateKey(_startedAt!);
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      recorderStartSec: 0.0,
      subScores: subScores,
      dateKey: dateKey,
      countsForDailyEffort: countsForDaily,
      completionPercent: completionPercent,
    );
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }

  Future<void> _completeAndPop(
      double score, Map<String, double>? subScores, {bool sessionEndedNormally = false}) async {
    await _saveAttempt(score: score, subScores: subScores, sessionEndedNormally: sessionEndedNormally);
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
          Text(
            widget.exercise.description,
            style: BalladTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (_preparing) 
            Text(
              'Starting in $_prepRemaining...',
              style: BalladTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          const Spacer(),
          Center(
            child: Text(
              '${remaining.toStringAsFixed(0)}s',
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w700,
                fontSize: 80,
                color: Colors.white,
              ),
            ),
          ),
          Center(
            child: Text(
              'Remaining',
              style: BalladTheme.bodyMedium.copyWith(color: Colors.white54),
            ),
          ),
          const Spacer(),
          const SizedBox(height: 12),
          if (_scorePct != null) ...[
            const SizedBox(height: 8),
            Text(
              'Score: ${_scorePct!.toStringAsFixed(0)}%',
               style: BalladTheme.titleMedium.copyWith(color: BalladTheme.accentTeal),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 56,
            child: BalladPrimaryButton(
              onPressed: _running ? _stop : _start,
              label: _running ? 'Stop' : 'Start',
              icon: _running ? Icons.stop : Icons.play_arrow,
            ),
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
    await _recording.start(owner: 'exercise');
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
    await _completeAndPop(_scorePct ?? 0, {'stability': _scorePct ?? 0}, sessionEndedNormally: false);
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
      {double? score, Map<String, double>? subScores, bool sessionEndedNormally = false}) async {
    if (_attemptSaved || score == null || _startedAt == null) return;
    final requiredSec = _holdGoalSec.round();
    final elapsedSec = _onPitchSec.round();
    final completionPercent = requiredSec <= 0 ? 0.0 : (elapsedSec / requiredSec).clamp(0.0, 1.0);
    final countsForDaily = DailyCompletionUtils.countsForDailyEffortCountdown(
      sessionEndedNormally: sessionEndedNormally,
      completionPercent: completionPercent,
      elapsedSec: elapsedSec,
      requiredSec: requiredSec,
    );
    final dateKey = DailyCompletionUtils.generateDateKey(_startedAt!);
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      recorderStartSec: 0.0,
      subScores: subScores,
      dateKey: dateKey,
      countsForDailyEffort: countsForDaily,
      completionPercent: completionPercent,
    );
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }

  Future<void> _completeAndPop(
      double score, Map<String, double>? subScores, {bool sessionEndedNormally = false}) async {
    await _saveAttempt(score: score, subScores: subScores, sessionEndedNormally: sessionEndedNormally);
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

// PitchMatchListeningPlayer replaced by PitchMatchingScreen
// Use PitchMatchingScreen in build method instead


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
    unawaited(_completeAndPop(_scorePct ?? 0, {'timing': _scorePct ?? 0}, sessionEndedNormally: false));
  }

  void _finish() {
    _running = false;
    _ticker?.stop();
    _lastTick = null;
    _scorePct = 100.0;
    unawaited(_completeAndPop(_scorePct ?? 0, {'timing': _scorePct ?? 0}, sessionEndedNormally: true));
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
      {double? score, Map<String, double>? subScores, bool sessionEndedNormally = false}) async {
    if (_attemptSaved || score == null || _startedAt == null) return;
    final targetSec = (widget.exercise.durationSeconds ?? 30).clamp(1, 999);
    final elapsedSec = _elapsed.round();
    final completionPercent = (elapsedSec / targetSec).clamp(0.0, 1.0);
    final countsForDaily = DailyCompletionUtils.countsForDailyEffortCountdown(
      sessionEndedNormally: sessionEndedNormally,
      completionPercent: completionPercent,
      elapsedSec: elapsedSec,
      requiredSec: targetSec,
    );
    final dateKey = DailyCompletionUtils.generateDateKey(_startedAt!);
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      recorderStartSec: 0.0,
      subScores: subScores,
      dateKey: dateKey,
      countsForDailyEffort: countsForDaily,
      completionPercent: completionPercent,
    );
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }

  Future<void> _completeAndPop(
      double score, Map<String, double>? subScores, {bool sessionEndedNormally = false}) async {
    await _saveAttempt(score: score, subScores: subScores, sessionEndedNormally: sessionEndedNormally);
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
    await _recording.start(owner: 'exercise');
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
    unawaited(_completeAndPop(_scorePct ?? 0, {'dynamics': _scorePct ?? 0}, sessionEndedNormally: false));
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
    unawaited(_completeAndPop(_scorePct ?? 0, {'dynamics': _scorePct ?? 0}, sessionEndedNormally: true));
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
      {double? score, Map<String, double>? subScores, bool sessionEndedNormally = false}) async {
    if (_attemptSaved || score == null || _startedAt == null) return;
    final targetSec = (widget.exercise.durationSeconds ?? 30).clamp(1, 999);
    final elapsedSec = _elapsed.round();
    final completionPercent = (elapsedSec / targetSec).clamp(0.0, 1.0);
    final countsForDaily = DailyCompletionUtils.countsForDailyEffortCountdown(
      sessionEndedNormally: sessionEndedNormally,
      completionPercent: completionPercent,
      elapsedSec: elapsedSec,
      requiredSec: targetSec,
    );
    final dateKey = DailyCompletionUtils.generateDateKey(_startedAt!);
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      recorderStartSec: 0.0,
      subScores: subScores,
      dateKey: dateKey,
      countsForDailyEffort: countsForDaily,
      completionPercent: completionPercent,
    );
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }

  Future<void> _completeAndPop(
      double score, Map<String, double>? subScores, {bool sessionEndedNormally = false}) async {
    await _saveAttempt(score: score, subScores: subScores, sessionEndedNormally: sessionEndedNormally);
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
    unawaited(_completeAndPop(_scorePct ?? 0, {'completion': _scorePct ?? 0}, sessionEndedNormally: false));
  }

  void _finish() {
    _running = false;
    _ticker?.stop();
    _lastTick = null;
    _scorePct = 100.0;
    unawaited(_completeAndPop(_scorePct ?? 0, {'completion': _scorePct ?? 0}, sessionEndedNormally: true));
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
      {double? score, Map<String, double>? subScores, bool sessionEndedNormally = false}) async {
    if (_attemptSaved || score == null || _startedAt == null) return;
    final targetSec = (widget.exercise.durationSeconds ?? 90).clamp(1, 999);
    final elapsedSec = _elapsed.round();
    final completionPercent = (elapsedSec / targetSec).clamp(0.0, 1.0);
    final countsForDaily = DailyCompletionUtils.countsForDailyEffortCountdown(
      sessionEndedNormally: sessionEndedNormally,
      completionPercent: completionPercent,
      elapsedSec: elapsedSec,
      requiredSec: targetSec,
    );
    final dateKey = DailyCompletionUtils.generateDateKey(_startedAt!);
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      recorderStartSec: 0.0,
      subScores: subScores,
      dateKey: dateKey,
      countsForDailyEffort: countsForDaily,
      completionPercent: completionPercent,
    );
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }

  Future<void> _completeAndPop(
      double score, Map<String, double>? subScores, {bool sessionEndedNormally = false}) async {
    await _saveAttempt(score: score, subScores: subScores, sessionEndedNormally: sessionEndedNormally);
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



