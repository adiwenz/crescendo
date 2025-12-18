import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';

import '../../models/pitch_frame.dart';
import '../../models/reference_note.dart';
import '../../models/take.dart';
import '../../services/audio_synth_service.dart';
import '../../services/recording_service.dart';
import '../../services/scoring_service.dart';
import '../../services/storage/take_repository.dart';
import '../state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/debug_overlay.dart';
import '../widgets/pitch_highway_painter.dart';
import '../../utils/performance_clock.dart';
import '../../utils/pitch_ball_controller.dart';
import '../../utils/pitch_state.dart';
import '../../utils/pitch_visual_state.dart';

class PitchHighwayScreen extends StatefulWidget {
  const PitchHighwayScreen({super.key});

  @override
  State<PitchHighwayScreen> createState() => _PitchHighwayScreenState();
}

class _PitchHighwayScreenState extends State<PitchHighwayScreen> with SingleTickerProviderStateMixin {
  final pixelsPerSecond = 160.0;
  final playheadFraction = 0.45;
  final tailWindowSec = 4.0;
  final midiRange = const (min: 48, max: 72);
  final double _leadInSec = 2.0;

  final _timeNotifier = ValueNotifier<double>(0);
  final _liveMidi = ValueNotifier<double?>(null);
  final _pitchTail = <PitchFrame>[];
  final _capturedFrames = <PitchFrame>[];
  final PerformanceClock _clock = PerformanceClock();
  final PitchBallController _pitchBall = PitchBallController();
  final PitchState _pitchState = PitchState();
  final PitchVisualState _visualState = PitchVisualState();
  static const _showDebugOverlay =
      bool.fromEnvironment('SHOW_PITCH_DEBUG', defaultValue: false);

  late final Ticker _ticker;
  bool _playing = false;
  bool _recordingActive = false;
  bool _audioStarted = false;

  late final RecordingService _recording;
  StreamSubscription<PitchFrame>? _liveSub;
  StreamSubscription<Duration>? _audioPosSub;
  late final AudioSynthService _synth;
  late final ScoringService _scoring;
  late final TakeRepository _repo;
  final appState = AppState();
  String? _referencePath;
  String? _lastRecordingPath;
  double? _audioPositionSec;
  double _manualOffsetMs = 0;
  late final double _audioLatencyMs;
  final double _pitchInputLatencyMs = 25;

  List<ReferenceNote> get _baseNotes => const [
        ReferenceNote(startSec: 0, endSec: 1.2, midi: 60, lyric: 'A'),
        ReferenceNote(startSec: 1.35, endSec: 2.4, midi: 62, lyric: 'new'),
        ReferenceNote(startSec: 2.5, endSec: 3.4, midi: 64, lyric: 'fan-'),
        ReferenceNote(startSec: 3.45, endSec: 4.4, midi: 65, lyric: 'tas-'),
        ReferenceNote(startSec: 4.6, endSec: 5.3, midi: 64, lyric: 'tic'),
        ReferenceNote(startSec: 5.5, endSec: 6.4, midi: 62, lyric: 'point'),
        ReferenceNote(startSec: 6.6, endSec: 7.2, midi: 60, lyric: 'of'),
        ReferenceNote(startSec: 7.35, endSec: 8.4, midi: 59, lyric: 'view'),
        ReferenceNote(startSec: 8.6, endSec: 9.6, midi: 60, lyric: 'yeah'),
      ];

  List<ReferenceNote> get _notesWithLeadIn => _baseNotes
      .map(
        (n) => ReferenceNote(
          startSec: n.startSec + _leadInSec,
          endSec: n.endSec + _leadInSec,
          midi: n.midi,
          lyric: n.lyric,
        ),
      )
      .toList();

  double get _totalDuration =>
      _notesWithLeadIn.map((n) => n.endSec).fold(0.0, math.max) +
      AudioSynthService.tailSeconds;

  @override
  void initState() {
    super.initState();
    _recording = RecordingService(bufferSize: 512);
    _synth = AudioSynthService();
    _scoring = ScoringService();
    _repo = TakeRepository();
    _ticker = createTicker(_onTick);
    _audioLatencyMs = kIsWeb ? 0 : (Platform.isIOS ? 100.0 : 150.0);
    _clock.setAudioPositionProvider(() => _audioPositionSec);
    _clock.setLatencyCompensationMs(_audioLatencyMs);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _liveSub?.cancel();
    _audioPosSub?.cancel();
    _recording.stop();
    _synth.stop();
    _timeNotifier.dispose();
    _liveMidi.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_playing) return;
    final now = _clock.nowSeconds();
    final effectiveMidi = _pitchState.effectiveMidi;
    final effectiveHz = _pitchState.effectiveHz;
    _visualState.update(
      timeSec: now,
      pitchHz: effectiveHz,
      pitchMidi: effectiveMidi,
      voiced: _pitchState.isVoiced,
    );
    _timeNotifier.value = now;
    _liveMidi.value = _visualState.visualPitchMidi;
    final visualMidi = _visualState.visualPitchMidi;
    if (visualMidi != null) {
      _pitchTail.add(PitchFrame(
        time: now,
        midi: visualMidi,
        voicedProb: _visualState.isVoiced ? 1.0 : 0.0,
      ));
    }
    _trimTail();
    if (now > _totalDuration) {
      unawaited(_togglePlayback(force: false));
    }
  }

  Future<void> _togglePlayback({bool? force}) async {
    final target = force ?? !_playing;
    if (target == _playing) return;
    if (target) {
      if (_timeNotifier.value >= _totalDuration) {
        _timeNotifier.value = 0;
        _pitchTail.clear();
        _capturedFrames.clear();
        _lastRecordingPath = null;
        _pitchBall.reset();
        _pitchState.reset();
        _visualState.reset();
      }
      _audioPositionSec = null;
      _audioStarted = false;
    _clock.setLatencyCompensationMs(_audioLatencyMs + _manualOffsetMs);
    _clock.start(offsetSec: _timeNotifier.value, freezeUntilAudio: true);
    _playing = true;
    _ticker.start();
    await _startRecording();
    await _playReference();
    } else {
      _playing = false;
      _ticker.stop();
      _clock.pause();
      await _stopRecording();
      await _synth.stop();
      await _audioPosSub?.cancel();
      _audioPosSub = null;
      _audioPositionSec = null;
      _liveMidi.value = null;
      _pitchState.reset();
      _visualState.reset();
    }
    setState(() {});
  }

  Future<void> _startRecording() async {
    _capturedFrames.clear();
    await _liveSub?.cancel();
    await _recording.start();
    _recordingActive = true;
    _liveSub = _recording.liveStream.listen((frame) {
      final midi = frame.midi ?? (frame.hz != null ? _hzToMidi(frame.hz!) : null);
      final now =
          (_clock.nowSeconds() - (_pitchInputLatencyMs / 1000.0)).clamp(-2.0, 3600.0);
      _handlePitchSample(
        time: now,
        hz: frame.hz,
        midi: midi,
        voicedProb: frame.voicedProb,
        rms: frame.rms,
      );
    });
  }

  void _trimTail() {
    final cutoff = _timeNotifier.value - tailWindowSec;
    final idx = _pitchTail.indexWhere((f) => f.time >= cutoff);
    if (idx > 0) {
      _pitchTail.removeRange(0, idx);
    } else if (idx == -1 && _pitchTail.isNotEmpty) {
      _pitchTail.clear();
    }
  }

  Future<void> _stopRecording() async {
    if (!_recordingActive) return;
    _recordingActive = false;
    await _liveSub?.cancel();
    _liveSub = null;
    final result = await _recording.stop();
    _lastRecordingPath = result.audioPath.isNotEmpty ? result.audioPath : _lastRecordingPath;
  }

  Future<String> _ensureReferenceAudio() async {
    if (_referencePath != null) return _referencePath!;
    _referencePath = await _synth.renderReferenceNotes(_notesWithLeadIn);
    return _referencePath!;
  }

  Future<void> _playReference() async {
    final path = await _ensureReferenceAudio();
    await _synth.stop();
    await _synth.playFile(path);
    await _audioPosSub?.cancel();
    _audioPosSub = _synth.onPositionChanged.listen((pos) {
      if (!_audioStarted && pos > Duration.zero) {
        _audioStarted = true;
      }
      if (_audioStarted) {
        _audioPositionSec = pos.inMilliseconds / 1000.0;
      }
    });
  }

  ReferenceNote? _noteAt(double t) {
    for (final n in _notesWithLeadIn) {
      if (t >= n.startSec && t <= n.endSec) return n;
    }
    return null;
  }

  List<PitchFrame> _attachCents(List<PitchFrame> frames) {
    return frames.map((f) {
      final note = _noteAt(f.time);
      if (note == null || f.midi == null) return f;
      final cents = (f.midi! - note.midi) * 100;
      return PitchFrame(time: f.time, hz: f.hz, midi: f.midi, centsError: cents);
    }).toList();
  }

  Future<void> _saveTake() async {
    if (_lastRecordingPath == null || _capturedFrames.isEmpty) return;
    final cleanFrames = _attachCents(_capturedFrames);
    final metrics = _scoring.score(cleanFrames);
    final take = Take(
      name: 'Pitch Highway ${DateTime.now().toLocal()}',
      createdAt: DateTime.now(),
      warmupId: 'pitch_highway_stub',
      warmupName: 'Pitch Highway',
      audioPath: _lastRecordingPath!,
      frames: cleanFrames,
      metrics: metrics,
    );
    await _repo.insert(take);
    appState.takesVersion.value++;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved take to history')));
    }
  }

  double _hzToMidi(double hz) => 69 + 12 * math.log(hz / 440) / math.ln2;

  void _handlePitchSample({
    required double time,
    required double? midi,
    double? hz,
    double? voicedProb,
    double? rms,
  }) {
    final voiced = midi != null && (voicedProb ?? 1.0) >= 0.6 && (rms ?? 1.0) >= 0.02;
    double? filtered;
    if (voiced) {
      _pitchBall.addSample(timeSec: time, midi: midi!);
      filtered = _pitchBall.lastSampleMidi ?? midi!;
      _pitchState.updateVoiced(timeSec: time, pitchHz: hz, pitchMidi: filtered);
    } else {
      _pitchState.updateUnvoiced(timeSec: time);
    }
    final f = PitchFrame(
      time: time,
      hz: hz,
      midi: voiced ? filtered : null,
      voicedProb: voicedProb,
      rms: rms,
    );
    _capturedFrames.add(f);
  }

  double _accuracyPercent() {
    if (_capturedFrames.isEmpty) return 0;
    final metrics = _scoring.score(_attachCents(_capturedFrames));
    return metrics.pctWithin50.clamp(0, 100);
  }

  String _formatTime(double t) {
    final totalSeconds = t.clamp(0, 24 * 60 * 60).floor();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _restart() async {
    if (_playing) {
      await _togglePlayback(force: false);
    }
    _timeNotifier.value = 0;
    _pitchTail.clear();
    _capturedFrames.clear();
    _lastRecordingPath = null;
    _pitchBall.reset();
    _pitchState.reset();
    _visualState.reset();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Pitch Highway'),
      ),
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePlayback,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: PitchHighwayPainter(
                      notes: _notesWithLeadIn,
                      pitchTail: _pitchTail,
                      time: _timeNotifier,
                      liveMidi: _liveMidi,
                      pitchTailTimeOffsetSec: 0,
                      pixelsPerSecond: pixelsPerSecond,
                      playheadFraction: playheadFraction,
                      drawBackground: false,
                      midiMin: midiRange.min,
                      midiMax: midiRange.max,
                      colors: colors,
                    ),
                  ),
                ),
                if (_showDebugOverlay)
                  DebugOverlay(
                    audioPositionMs:
                        _audioPositionSec == null ? null : _audioPositionSec! * 1000.0,
                    visualTimeMs: _timeNotifier.value * 1000.0,
                    pitchLagMs: _pitchBall.estimateLagMs(_timeNotifier.value),
                    offsetMs: _manualOffsetMs,
                    onOffsetChange: (value) {
                      setState(() => _manualOffsetMs = value);
                      _clock.setLatencyCompensationMs(_audioLatencyMs + _manualOffsetMs);
                    },
                    label: 'Pitch Highway',
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ValueListenableBuilder<double>(
                            valueListenable: _timeNotifier,
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
                                  valueListenable: _timeNotifier,
                                  builder: (_, v, __) {
                                    final pct = (v / _totalDuration).clamp(0.0, 1.0);
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
                            _formatTime(_totalDuration),
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
