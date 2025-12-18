import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
import '../widgets/pitch_highway_painter.dart';

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

  final _timeNotifier = ValueNotifier<double>(0);
  final _pitchTail = <PitchFrame>[];
  final _capturedFrames = <PitchFrame>[];

  late final Ticker _ticker;
  Duration? _lastTick;
  bool _playing = false;
  bool _recordingActive = false;

  late final RecordingService _recording;
  StreamSubscription<PitchFrame>? _liveSub;
  late final AudioSynthService _synth;
  late final ScoringService _scoring;
  late final TakeRepository _repo;
  final appState = AppState();
  String? _referencePath;
  String? _lastRecordingPath;

  List<ReferenceNote> get _stubNotes => const [
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

  double get _totalDuration =>
      _stubNotes.map((n) => n.endSec).fold(0.0, math.max) + AudioSynthService.tailSeconds;

  @override
  void initState() {
    super.initState();
    _recording = RecordingService();
    _synth = AudioSynthService();
    _scoring = ScoringService();
    _repo = TakeRepository();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _liveSub?.cancel();
    _recording.stop();
    _synth.stop();
    _timeNotifier.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_playing) return;
    final dt = elapsed - (_lastTick ?? elapsed);
    _lastTick = elapsed;
    _advance(dt.inMicroseconds / 1e6);
  }

  void _advance(double deltaSeconds) {
    final next = _timeNotifier.value + deltaSeconds;
    _timeNotifier.value = next;
    _trimTail();
    if (next > _totalDuration) {
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
      }
      _playing = true;
      _lastTick = null;
      _ticker.start();
      await _startRecording();
      await _playReference();
    } else {
      _playing = false;
      _ticker.stop();
      _lastTick = null;
      await _stopRecording();
      await _synth.stop();
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
      if (midi == null) return;
      final now = _timeNotifier.value;
      final f = PitchFrame(time: now, hz: frame.hz, midi: midi);
      _pitchTail.add(f);
      _capturedFrames.add(f);
      _trimTail();
      _timeNotifier.value = _timeNotifier.value;
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
    _referencePath = await _synth.renderReferenceNotes(_stubNotes);
    return _referencePath!;
  }

  Future<void> _playReference() async {
    final path = await _ensureReferenceAudio();
    await _synth.stop();
    await _synth.playFile(path);
  }

  ReferenceNote? _noteAt(double t) {
    for (final n in _stubNotes) {
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
                      notes: _stubNotes,
                      pitchTail: _pitchTail,
                      time: _timeNotifier,
                      pixelsPerSecond: pixelsPerSecond,
                      playheadFraction: playheadFraction,
                      drawBackground: false,
                      midiMin: midiRange.min,
                      midiMax: midiRange.max,
                      colors: colors,
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
