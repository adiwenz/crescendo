import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/pitch_frame.dart';
import '../../models/pitch_highway_difficulty.dart';
import '../../models/pitch_highway_spec.dart';
import '../../models/reference_note.dart';
import '../../models/vocal_exercise.dart';
import '../../models/last_take.dart';
import '../../services/audio_synth_service.dart';
import '../../services/last_take_store.dart';
import '../../services/progress_service.dart';
import '../../services/recording_service.dart';
import '../../services/robust_note_scoring_service.dart';
import '../../services/unlock_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/pitch_highway_painter.dart';
import '../../utils/pitch_math.dart';
import '../../utils/pitch_highway_tempo.dart';
import 'level_up_screen.dart';

class ExercisePlayerScreen extends StatelessWidget {
  final VocalExercise exercise;
  final PitchHighwayDifficulty? pitchDifficulty;

  const ExercisePlayerScreen({
    super.key,
    required this.exercise,
    this.pitchDifficulty,
  });

  @override
  Widget build(BuildContext context) {
    final isPitchHighway = exercise.type == ExerciseType.pitchHighway;
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
      body: switch (exercise.type) {
        ExerciseType.pitchHighway => PitchHighwayPlayer(
            exercise: exercise,
            showBackButton: true,
            pitchDifficulty: pitchDifficulty ?? PitchHighwayDifficulty.medium,
          ),
        ExerciseType.breathTimer => BreathTimerPlayer(exercise: exercise),
        ExerciseType.sovtTimer => SovtTimerPlayer(exercise: exercise),
        ExerciseType.sustainedPitchHold => SustainedPitchHoldPlayer(exercise: exercise),
        ExerciseType.pitchMatchListening => PitchMatchListeningPlayer(exercise: exercise),
        ExerciseType.articulationRhythm => ArticulationRhythmPlayer(exercise: exercise),
        ExerciseType.dynamicsRamp => DynamicsRampPlayer(exercise: exercise),
        ExerciseType.cooldownRecovery => CooldownRecoveryPlayer(exercise: exercise),
      },
    );
  }
}

class PitchHighwayPlayer extends StatefulWidget {
  final VocalExercise exercise;
  final bool showBackButton;
  final PitchHighwayDifficulty pitchDifficulty;

  const PitchHighwayPlayer({
    super.key,
    required this.exercise,
    this.showBackButton = false,
    required this.pitchDifficulty,
  });

  @override
  State<PitchHighwayPlayer> createState() => _PitchHighwayPlayerState();
}

class _PitchHighwayPlayerState extends State<PitchHighwayPlayer>
    with SingleTickerProviderStateMixin {
  final AudioSynthService _synth = AudioSynthService();
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  final List<PitchFrame> _tail = [];
  final List<PitchFrame> _captured = [];
  final ProgressService _progress = ProgressService();
  final LastTakeStore _lastTakeStore = LastTakeStore();
  final UnlockService _unlockService = UnlockService();
  final _tailWindowSec = 4.0;
  Ticker? _ticker;
  Duration? _lastTick;
  bool _playing = false;
  bool _preparing = false;
  int _prepRemaining = 0;
  Timer? _prepTimer;
  int _prepRunId = 0;
  bool _captureEnabled = false;
  bool _useMic = true;
  int _transpose = 0;
  RecordingService? _recording;
  StreamSubscription<PitchFrame>? _sub;
  double? _scorePct;
  DateTime? _startedAt;
  bool _attemptSaved = false;
  late final PitchHighwaySpec? _scaledSpec;

  double get _durationSec {
    final base = (_scaledSpec?.totalMs ?? 0) / 1000.0;
    if (base <= 0) return 0.0;
    return base + AudioSynthService.tailSeconds;
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _scaledSpec = _buildScaledSpec();
  }

  PitchHighwaySpec? _buildScaledSpec() {
    final spec = widget.exercise.highwaySpec;
    if (spec == null || spec.segments.isEmpty) return spec;
    final tempoMultiplier = PitchHighwayTempo.multiplierFor(
      widget.pitchDifficulty,
      spec.segments,
    );
    final scaledSegments = PitchHighwayTempo.scaleSegments(
      spec.segments,
      tempoMultiplier,
    );
    return PitchHighwaySpec(segments: scaledSegments);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _sub?.cancel();
    _recording?.stop();
    _prepTimer?.cancel();
    _synth.stop();
    _time.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_playing) return;
    final dt = elapsed - (_lastTick ?? elapsed);
    _lastTick = elapsed;
    final next = _time.value + dt.inMicroseconds / 1e6;
    _time.value = next;
    _trimTail();
    if (!_useMic) {
      _simulatePitch(next);
    }
    if (next >= _durationSec) {
      _stop();
    }
  }

  void _trimTail() {
    final cutoff = _time.value - _tailWindowSec;
    final idx = _tail.indexWhere((f) => f.time >= cutoff);
    if (idx > 0) {
      _tail.removeRange(0, idx);
    } else if (idx == -1 && _tail.isNotEmpty) {
      _tail.clear();
    }
  }

  Future<void> _start() async {
    if (_playing || _preparing) return;
    _prepRunId += 1;
    final runId = _prepRunId;
    _scorePct = null;
    _attemptSaved = false;
    _startedAt = DateTime.now();
    _captured.clear();
    _tail.clear();
    _captureEnabled = false;
    _time.value = -2.0;
    _playing = true;
    _lastTick = null;
    _ticker?.start();
    _beginPrepCountdown();
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted || !_preparing || runId != _prepRunId) return;
    _endPrepCountdown();
    _captureEnabled = true;
    if (_useMic) {
      _recording = RecordingService();
      await _recording?.start();
      _sub = _recording?.liveStream.listen((frame) {
        if (!_captureEnabled) return;
        final midi = frame.midi ??
            (frame.hz != null ? 69 + 12 * math.log(frame.hz! / 440.0) / math.ln2 : null);
        if (midi == null) return;
        final pf = PitchFrame(
          time: _time.value,
          hz: frame.hz,
          midi: midi,
          voicedProb: frame.voicedProb,
          rms: frame.rms,
        );
        _tail.add(pf);
        _captured.add(pf);
        _trimTail();
      });
    }
    await _playReference();
    setState(() {});
  }

  Future<void> _stop() async {
    if (!_playing && !_preparing) return;
    _endPrepCountdown();
    _playing = false;
    _captureEnabled = false;
    _ticker?.stop();
    _lastTick = null;
    await _sub?.cancel();
    _sub = null;
    final recordingResult = _recording == null ? null : await _recording!.stop();
    _recording = null;
    await _synth.stop();
    await _saveLastTake(recordingResult?.audioPath);
    final score = _scorePct ?? _computeScore();
    _scorePct = score;
    await _completeAndPop(score, {'intonation': score});
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

  void _simulatePitch(double t) {
    // TODO: Replace simulation with real pitch stream if mic is unavailable.
    if (!_captureEnabled) return;
    final targetMidi = _targetMidiAtTime(t);
    if (targetMidi == null) return;
    final vibrato = math.sin(t * 2 * math.pi * 5) * 0.2;
    final midi = targetMidi + vibrato;
    final hz = 440.0 * math.pow(2.0, (midi - 69) / 12.0);
    final pf = PitchFrame(time: t, hz: hz, midi: midi);
    _tail.add(pf);
    _captured.add(pf);
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

  double? _targetMidiAtTime(double t) {
    final spec = _scaledSpec;
    if (spec == null) return null;
    final ms = (t * 1000).round();
    for (final seg in spec.segments) {
      if (ms < seg.startMs || ms > seg.endMs) continue;
      if (seg.isGlide) {
        final start = seg.startMidi ?? seg.midiNote;
        final end = seg.endMidi ?? seg.midiNote;
        final ratio = (ms - seg.startMs) / math.max(1, seg.endMs - seg.startMs);
        return (start + (end - start) * ratio) + _transpose;
      }
      return (seg.midiNote + _transpose).toDouble();
    }
    return null;
  }

  String? _labelAtTime(double t) {
    final spec = _scaledSpec;
    if (spec == null) return null;
    final ms = (t * 1000).round();
    for (final seg in spec.segments) {
      if (ms >= seg.startMs && ms <= seg.endMs) return seg.label;
    }
    return null;
  }

  List<ReferenceNote> _buildReferenceNotes() {
    final spec = _scaledSpec;
    if (spec == null) return const [];
    final notes = <ReferenceNote>[];
    for (final seg in spec.segments) {
      if (seg.isGlide) {
        final startMidi = seg.startMidi ?? seg.midiNote;
        final endMidi = seg.endMidi ?? seg.midiNote;
        final durationMs = seg.endMs - seg.startMs;
        final steps = math.max(4, (durationMs / 200).round());
        for (var i = 0; i < steps; i++) {
          final ratio = i / steps;
          final midi = (startMidi + (endMidi - startMidi) * ratio).round();
          final stepStart = seg.startMs + (durationMs * ratio).round();
          final stepEnd = seg.startMs + (durationMs * ((i + 1) / steps)).round();
          notes.add(ReferenceNote(
            startSec: stepStart / 1000.0,
            endSec: stepEnd / 1000.0,
            midi: midi + _transpose,
            lyric: seg.label,
          ));
        }
      } else {
        notes.add(ReferenceNote(
          startSec: seg.startMs / 1000.0,
          endSec: seg.endMs / 1000.0,
          midi: seg.midiNote + _transpose,
          lyric: seg.label,
        ));
      }
    }
    return notes;
  }

  Future<void> _playReference() async {
    final colors = AppThemeColors.of(context);
    final notes = _buildReferenceNotes();
    if (notes.isEmpty) return;
    final path = await _synth.renderReferenceNotes(notes);
    await _synth.playFile(path);
  }

  double _computeScore() {
    final notes = _buildReferenceNotes();
    if (notes.isEmpty || _captured.isEmpty) return 0.0;
    final result = RobustNoteScoringService().score(notes: notes, frames: _captured);
    return result.overallScorePct;
  }

  Future<void> _saveAttempt({double? score, Map<String, double>? subScores}) async {
    if (_attemptSaved || score == null || _startedAt == null) return;
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      subScores: subScores,
      pitchDifficulty: widget.pitchDifficulty.name,
    );
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }

  Future<void> _completeAndPop(double score, Map<String, double>? subScores) async {
    await _saveAttempt(score: score, subScores: subScores);
    if (!mounted) return;
    final levelResult = await _unlockService.applyResult(
      exerciseId: widget.exercise.id,
      difficulty: widget.pitchDifficulty,
      score: score.round(),
    );
    if (levelResult.levelUp && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LevelUpScreen(
            exerciseName: widget.exercise.name,
            score: score.round(),
            unlockedDifficulty: levelResult.unlockedDifficulty,
          ),
        ),
      );
    }
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(score);
    }
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
    final midiValues = notes.map((n) => n.midi).toList();
    final minMidi = midiValues.isNotEmpty ? (midiValues.reduce(math.min) - 4) : 48;
    final maxMidi = midiValues.isNotEmpty ? (midiValues.reduce(math.max) + 4) : 72;
    final totalDuration = _durationSec > 0 ? _durationSec : 1.0;
    final difficultyLabel = pitchHighwayDifficultyLabel(widget.pitchDifficulty);
    return AppBackground(
      child: SafeArea(
        bottom: false,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _playing || _preparing ? _stop : _start,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: PitchHighwayPainter(
                    notes: notes,
                    pitchTail: _tail,
                    time: _time,
                    drawBackground: false,
                    midiMin: minMidi,
                    midiMax: maxMidi,
                    colors: colors,
                  ),
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
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(Icons.arrow_back, color: colors.textPrimary),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: widget.showBackButton ? 52 : 12,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.surface2,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: colors.borderSubtle),
                  ),
                  child: Text(
                    difficultyLabel,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: colors.textSecondary, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              if (_preparing)
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Starting in $_prepRemaining...',
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
                            padding: const EdgeInsets.symmetric(horizontal: 12),
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
                                  final pct = (v / totalDuration).clamp(0.0, 1.0);
                                  return FractionallySizedBox(
                                    widthFactor: pct,
                                    child: Container(
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: colors.blueAccent,
                                        borderRadius: BorderRadius.circular(3),
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
    final target = (widget.exercise.durationSeconds ?? 30).clamp(0, 30).toDouble();
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
    final target = (widget.exercise.durationSeconds ?? 30).clamp(0, 30).toDouble();
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

  Future<void> _saveAttempt({double? score, Map<String, double>? subScores}) async {
    if (_attemptSaved || score == null || _startedAt == null) return;
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      subScores: subScores,
    );
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }

  Future<void> _completeAndPop(double score, Map<String, double>? subScores) async {
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
          Text(current.label, style: Theme.of(context).textTheme.headlineMedium),
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
  bool _phonationOn = true;
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
    final target = (widget.exercise.durationSeconds ?? 30).clamp(0, 30).toDouble();
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
    final target = (widget.exercise.durationSeconds ?? 30).clamp(0, 30).toDouble();
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

  Future<void> _saveAttempt({double? score, Map<String, double>? subScores}) async {
    if (_attemptSaved || score == null || _startedAt == null) return;
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      subScores: subScores,
    );
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }

  Future<void> _completeAndPop(double score, Map<String, double>? subScores) async {
    await _saveAttempt(score: score, subScores: subScores);
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(score);
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = (widget.exercise.durationSeconds ?? 30).clamp(0, 30).toDouble();
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
          SwitchListTile(
            title: const Text('Phonation on/off'),
            value: _phonationOn,
            onChanged: (v) => setState(() => _phonationOn = v),
          ),
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

class SustainedPitchHoldPlayer extends StatefulWidget {
  final VocalExercise exercise;

  const SustainedPitchHoldPlayer({super.key, required this.exercise});

  @override
  State<SustainedPitchHoldPlayer> createState() => _SustainedPitchHoldPlayerState();
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
  double _centsError = 0;
  double _onPitchSec = 0;
  double _listeningSec = 0;
  double _lastTime = 0;
  final _holdGoalSec = 3.0;
  double? _scorePct;
  DateTime? _startedAt;
  bool _attemptSaved = false;

  @override
  void dispose() {
    _sub?.cancel();
    _recording.stop();
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
    await _recording.start();
    _lastTime = 0;
    _onPitchSec = 0;
    _listeningSec = 0;
    _attemptSaved = false;
    _startedAt = DateTime.now();
    _sub = _recording.liveStream.listen((frame) {
      final hz = frame.hz;
      if (hz == null || hz <= 0) return;
      final cents = 1200 * (math.log(hz / _targetHz) / math.ln2);
      final dt = _lastTime == 0 ? 0 : math.max(0, frame.time - _lastTime);
      _lastTime = frame.time;
      if (dt > 0) {
        _listeningSec += dt;
      }
      final voiced = (frame.voicedProb ?? 1.0) >= 0.6 && (frame.rms ?? 1.0) >= 0.02;
      if (voiced && cents.abs() <= 25) {
        _onPitchSec += dt;
      } else if (dt > 0.2) {
        _onPitchSec = 0;
      }
      setState(() => _centsError = cents);
    });
    _scorePct = null;
    setState(() => _listening = true);
  }

  Future<void> _stop() async {
    if (!_listening && !_preparing) return;
    _endPrepCountdown();
    await _sub?.cancel();
    await _recording.stop();
    _sub = null;
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

  Future<void> _saveAttempt({double? score, Map<String, double>? subScores}) async {
    if (_attemptSaved || score == null || _startedAt == null) return;
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      subScores: subScores,
    );
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }

  Future<void> _completeAndPop(double score, Map<String, double>? subScores) async {
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.exercise.description),
          const SizedBox(height: 12),
          if (_preparing) Text('Starting in $_prepRemaining...'),
          Text('Target: MIDI $_targetMidi', style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: _targetMidi.toDouble(),
            min: 48,
            max: 72,
            divisions: 24,
            label: _targetMidi.toString(),
            onChanged: (v) => setState(() => _targetMidi = v.round()),
          ),
          const SizedBox(height: 8),
          Text('${_centsError.toStringAsFixed(1)} cents',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
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

class PitchMatchListeningPlayer extends StatefulWidget {
  final VocalExercise exercise;

  const PitchMatchListeningPlayer({super.key, required this.exercise});

  @override
  State<PitchMatchListeningPlayer> createState() => _PitchMatchListeningPlayerState();
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

  @override
  void dispose() {
    _sub?.cancel();
    _recording.stop();
    _prepTimer?.cancel();
    _synth.stop();
    super.dispose();
  }

  double get _targetHz => 440.0 * math.pow(2.0, (_targetMidi - 69) / 12.0);

  Future<void> _playTone() async {
    final notes = [
      ReferenceNote(startSec: 0, endSec: 1.2, midi: _targetMidi),
    ];
    final path = await _synth.renderReferenceNotes(notes);
    await _synth.playFile(path);
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
    });
    _scorePct = null;
    setState(() => _listening = true);
  }

  Future<void> _stop() async {
    if (!_listening && !_preparing) return;
    _endPrepCountdown();
    await _sub?.cancel();
    await _recording.stop();
    _sub = null;
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

  Future<void> _saveAttempt({double? score, Map<String, double>? subScores}) async {
    if (_attemptSaved || score == null || _startedAt == null) return;
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      subScores: subScores,
    );
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }

  Future<void> _completeAndPop(double score, Map<String, double>? subScores) async {
    await _saveAttempt(score: score, subScores: subScores);
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(score);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.exercise.description),
          const SizedBox(height: 12),
          if (_preparing) Text('Starting in $_prepRemaining...'),
          Text('Target: MIDI $_targetMidi', style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: _targetMidi.toDouble(),
            min: 48,
            max: 72,
            divisions: 24,
            label: _targetMidi.toString(),
            onChanged: (v) => setState(() => _targetMidi = v.round()),
          ),
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
                  label: const Text('Replay tone'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ArticulationRhythmPlayer extends StatefulWidget {
  final VocalExercise exercise;

  const ArticulationRhythmPlayer({super.key, required this.exercise});

  @override
  State<ArticulationRhythmPlayer> createState() => _ArticulationRhythmPlayerState();
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
    final target = (widget.exercise.durationSeconds ?? 30).clamp(0, 30).toDouble();
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
    final target = (widget.exercise.durationSeconds ?? 30).clamp(0, 30).toDouble();
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

  Future<void> _saveAttempt({double? score, Map<String, double>? subScores}) async {
    if (_attemptSaved || score == null || _startedAt == null) return;
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      subScores: subScores,
    );
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }

  Future<void> _completeAndPop(double score, Map<String, double>? subScores) async {
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
                backgroundColor: active ? Colors.blue.shade200 : Colors.grey.shade200,
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

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _sub?.cancel();
    _recording.stop();
    _prepTimer?.cancel();
    _synth.stop();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_running) return;
    final dt = elapsed - (_lastTick ?? elapsed);
    _lastTick = elapsed;
    final next = _elapsed + dt.inMicroseconds / 1e6;
    final target = (widget.exercise.durationSeconds ?? 30).clamp(0, 30).toDouble();
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
    await _recording.start();
    _sampleTimes.clear();
    _sampleRms.clear();
    _attemptSaved = false;
    _startedAt = DateTime.now();
    _sub = _recording.liveStream.listen((frame) {
      final rms = frame.rms ?? 0.0;
      _sampleTimes.add(_elapsed);
      _sampleRms.add(rms);
      setState(() => _rms = rms);
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
    _recording.stop();
    unawaited(_completeAndPop(_scorePct ?? 0, {'dynamics': _scorePct ?? 0}));
  }

  void _finish() {
    _running = false;
    _ticker?.stop();
    _lastTick = null;
    _scorePct = _computeScore();
    _sub?.cancel();
    _recording.stop();
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
    final duration = (widget.exercise.durationSeconds ?? 30).clamp(0, 30).toDouble();
    double sumDiff = 0.0;
    for (var i = 0; i < _sampleTimes.length; i++) {
      final progress = (_sampleTimes[i] / duration).clamp(0.0, 1.0);
      final target = progress <= 0.5 ? (progress * 2) : (1 - (progress - 0.5) * 2);
      final diff = (target - _sampleRms[i]).abs();
      sumDiff += diff;
    }
    final meanDiff = sumDiff / _sampleTimes.length;
    return (1.0 - meanDiff.clamp(0.0, 1.0)) * 100.0;
  }

  Future<void> _saveAttempt({double? score, Map<String, double>? subScores}) async {
    if (_attemptSaved || score == null || _startedAt == null) return;
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      subScores: subScores,
    );
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }

  Future<void> _completeAndPop(double score, Map<String, double>? subScores) async {
    await _saveAttempt(score: score, subScores: subScores);
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(score);
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = (widget.exercise.durationSeconds ?? 30).clamp(0, 30).toDouble();
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

  Future<void> _saveAttempt({double? score, Map<String, double>? subScores}) async {
    if (_attemptSaved || score == null || _startedAt == null) return;
    final attempt = _progress.buildAttempt(
      exerciseId: widget.exercise.id,
      categoryId: widget.exercise.categoryId,
      startedAt: _startedAt!,
      completedAt: DateTime.now(),
      overallScore: score.clamp(0.0, 100.0),
      subScores: subScores,
    );
    _attemptSaved = true;
    await _progress.saveAttempt(attempt);
  }

  Future<void> _completeAndPop(double score, Map<String, double>? subScores) async {
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
