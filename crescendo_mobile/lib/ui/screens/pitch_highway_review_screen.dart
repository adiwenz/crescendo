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
import '../../services/audio_synth_service.dart';
import '../../services/transposed_exercise_builder.dart';
import '../../services/vocal_range_service.dart';
import '../../utils/pitch_highway_tempo.dart';
import '../../utils/pitch_math.dart';
import '../../utils/performance_clock.dart';
import '../../utils/exercise_constants.dart';
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
  final AudioSynthService _synth = AudioSynthService();
  final VocalRangeService _vocalRangeService = VocalRangeService();
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  final PerformanceClock _clock = PerformanceClock();
  Ticker? _ticker;
  bool _playing = false;
  StreamSubscription<Duration>? _audioPosSub;
  double? _audioPositionSec;
  bool _audioStarted = false;
  late final double _audioLatencyMs;
  List<ReferenceNote> _notes = const [];
  double _durationSec = 1.0;
  // Use shared constant for lead-in time
  static const double _leadInSec = ExerciseConstants.leadInSec;
  bool _loggedGraphInfo = false;
  late final double _pixelsPerSecond;

  @override
  void initState() {
    super.initState();
    final difficulty =
        pitchHighwayDifficultyFromName(widget.lastTake.pitchDifficulty) ??
            PitchHighwayDifficulty.medium;
    _pixelsPerSecond = PitchHighwayTempo.pixelsPerSecondFor(difficulty);
    _ticker = createTicker(_onTick);
    _audioLatencyMs = kIsWeb ? 0 : (Platform.isIOS ? 100.0 : 150.0);
    _clock.setAudioPositionProvider(() => _audioPositionSec);
    _clock.setLatencyCompensationMs(-_audioLatencyMs);
    _time.value = widget.startTimeSec;
    _loadTransposedNotes(difficulty);
  }

  Future<void> _loadTransposedNotes(PitchHighwayDifficulty difficulty) async {
    final (lowestMidi, highestMidi) = await _vocalRangeService.getRange();
    final notes = TransposedExerciseBuilder.buildTransposedSequence(
      exercise: widget.exercise,
      lowestMidi: lowestMidi,
      highestMidi: highestMidi,
      leadInSec: _leadInSec,
      difficulty: difficulty,
    );
    if (mounted) {
      setState(() {
        _notes = notes;
        _durationSec = _computeDuration(notes);
      });
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _audioPosSub?.cancel();
    _synth.stop();
    _time.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_playing) return;
    final next = _clock.nowSeconds();
    _time.value = next;
    if (next >= _durationSec) {
      _stop();
    }
  }

  Future<void> _start() async {
    if (_playing) return;
    if (_time.value >= _durationSec) {
      _time.value = widget.startTimeSec;
    }
    if (_time.value < widget.startTimeSec) {
      _time.value = widget.startTimeSec;
    }
    _playing = true;
    _audioPositionSec = null;
    _audioStarted = false;
    _clock.setLatencyCompensationMs(-_audioLatencyMs);
    _clock.start(offsetSec: _time.value, freezeUntilAudio: true);
    _ticker?.start();
    await _playAudio();
    if (mounted) setState(() {});
  }

  Future<void> _stop() async {
    if (!_playing) return;
    _playing = false;
    _ticker?.stop();
    _clock.pause();
    await _audioPosSub?.cancel();
    _audioPosSub = null;
    await _synth.stop();
    if (mounted) setState(() {});
  }

  Future<void> _playAudio() async {
    final audioPath = widget.lastTake.audioPath;
    if (audioPath != null && audioPath.isNotEmpty) {
      final file = File(audioPath);
      if (await file.exists()) {
        // For review mode: delay audio playback by lead-in to match visual timeline
        // Chart time starts at 0, audio should start after lead-in period
        await Future.delayed(Duration(milliseconds: ExerciseConstants.leadInMs));
        await _synth.playFile(audioPath);
        await _audioPosSub?.cancel();
        _audioPosSub = _synth.onPositionChanged.listen((pos) {
          if (!_audioStarted && pos > Duration.zero) {
            _audioStarted = true;
          }
          if (_audioStarted) {
            // Audio position is relative to audio file start, but chart time includes lead-in
            // So we add the lead-in to sync with chart time
            _audioPositionSec = (pos.inMilliseconds / 1000.0) + _leadInSec;
          }
        });
        return;
      }
    }
    await _playReference();
  }

  Future<void> _playReference() async {
    if (_notes.isEmpty) return;
    final path = await _synth.renderReferenceNotes(_notes);
    // Reference notes already have lead-in built in (first note starts at leadInSec)
    // So audio will have 2 seconds of silence at the start, which matches the visual lead-in
    await _synth.playFile(path);
    await _audioPosSub?.cancel();
    _audioPosSub = _synth.onPositionChanged.listen((pos) {
      if (!_audioStarted && pos > Duration.zero) {
        _audioStarted = true;
      }
      if (_audioStarted) {
        // Audio position is relative to audio file start, which includes lead-in silence
        // Chart time also includes lead-in, so they should be in sync
        _audioPositionSec = pos.inMilliseconds / 1000.0;
      }
    });
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
    final combined = [...noteMidis, ...contourMidis];
    final minMidi = combined.isNotEmpty
        ? (combined.reduce(math.min).floor() - 3)
        : 48;
    final maxMidi = combined.isNotEmpty
        ? (combined.reduce(math.max).ceil() + 3)
        : 72;
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
            onTap: _playing ? _stop : _start,
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
                          noteTimeOffsetSec: _leadInSec,
                          colors: colors,
                          debugLogMapping: true,
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
