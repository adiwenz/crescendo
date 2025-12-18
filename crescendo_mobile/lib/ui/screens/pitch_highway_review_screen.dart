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
import '../../models/pitch_segment.dart';
import '../../models/exercise_instance.dart';
import '../../services/audio_synth_service.dart';
import '../../services/range_exercise_generator.dart';
import '../../services/range_store.dart';
import '../../utils/pitch_highway_tempo.dart';
import '../../utils/performance_clock.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/pitch_contour_painter.dart';
import '../widgets/pitch_highway_painter.dart';

class PitchHighwayReviewScreen extends StatefulWidget {
  final VocalExercise exercise;
  final LastTake lastTake;

  const PitchHighwayReviewScreen({
    super.key,
    required this.exercise,
    required this.lastTake,
  });

  @override
  State<PitchHighwayReviewScreen> createState() => _PitchHighwayReviewScreenState();
}

class _PitchHighwayReviewScreenState extends State<PitchHighwayReviewScreen>
    with SingleTickerProviderStateMixin {
  final AudioSynthService _synth = AudioSynthService();
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  final PerformanceClock _clock = PerformanceClock();
  Ticker? _ticker;
  bool _playing = false;
  StreamSubscription<Duration>? _audioPosSub;
  double? _audioPositionSec;
  bool _audioStarted = false;
  late final double _audioLatencyMs;
  final _rangeStore = RangeStore();
  final _rangeGenerator = RangeExerciseGenerator();
  List<ReferenceNote> _notes = const [];
  double _durationSec = 1.0;
  final double _leadInSec = 2.0;

  @override
  void initState() {
    super.initState();
    final difficulty =
        pitchHighwayDifficultyFromName(widget.lastTake.pitchDifficulty) ??
            PitchHighwayDifficulty.medium;
    _notes = _buildReferenceNotes(widget.exercise, difficulty);
    _durationSec = _computeDuration(_notes);
    unawaited(_loadRangeNotes(widget.exercise, difficulty));
    _ticker = createTicker(_onTick);
    _audioLatencyMs = kIsWeb ? 0 : (Platform.isIOS ? 100.0 : 150.0);
    _clock.setAudioPositionProvider(() => _audioPositionSec);
    _clock.setLatencyCompensationMs(-_audioLatencyMs);
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
      _time.value = 0;
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
        await _synth.playFile(audioPath);
        await _audioPosSub?.cancel();
        _audioPosSub = _synth.onPositionChanged.listen((pos) {
          if (!_audioStarted && pos > Duration.zero) {
            _audioStarted = true;
          }
          if (_audioStarted) {
            _audioPositionSec = pos.inMilliseconds / 1000.0;
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

  Future<void> _loadRangeNotes(
    VocalExercise exercise,
    PitchHighwayDifficulty difficulty,
  ) async {
    final range = await _rangeStore.getRange();
    final lowest = range.$1;
    final highest = range.$2;
    if (!mounted || lowest == null || highest == null) return;
    final instances = _rangeGenerator.generate(
      exercise: exercise,
      lowestMidi: lowest,
      highestMidi: highest,
    );
    if (instances.isEmpty) return;
    final scaledSegments = _scaledSegments(exercise, difficulty);
    final stitched = _concatenateSegments(scaledSegments, instances);
    final notes = _segmentsToNotes(stitched);
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _durationSec = _computeDuration(notes);
    });
  }

  double _computeDuration(List<ReferenceNote> notes) {
    final specDuration =
        notes.isEmpty ? 0.0 : notes.map((n) => n.endSec).fold(0.0, math.max);
    return math.max(widget.lastTake.durationSec, specDuration) +
        AudioSynthService.tailSeconds;
  }

  List<PitchSegment> _scaledSegments(
    VocalExercise exercise,
    PitchHighwayDifficulty difficulty,
  ) {
    final spec = exercise.highwaySpec;
    if (spec == null) return const [];
    final multiplier =
        PitchHighwayTempo.multiplierFor(difficulty, spec.segments);
    return PitchHighwayTempo.scaleSegments(spec.segments, multiplier);
  }

  List<PitchSegment> _concatenateSegments(
    List<PitchSegment> baseSegments,
    List<ExerciseInstance> instances,
  ) {
    const gapMs = 1000;
    final stitched = <PitchSegment>[];
    var cursorMs = 0;
    for (final instance in instances) {
      var localEnd = 0;
      for (final seg in baseSegments) {
        stitched.add(PitchSegment(
          startMs: seg.startMs + cursorMs,
          endMs: seg.endMs + cursorMs,
          midiNote: seg.midiNote + instance.transposeSemitones,
          toleranceCents: seg.toleranceCents,
          label: seg.label,
          startMidi: seg.startMidi != null
              ? seg.startMidi! + instance.transposeSemitones
              : null,
          endMidi: seg.endMidi != null
              ? seg.endMidi! + instance.transposeSemitones
              : null,
        ));
        if (seg.endMs > localEnd) localEnd = seg.endMs;
      }
      cursorMs += localEnd + gapMs;
    }
    return stitched;
  }

  List<ReferenceNote> _buildReferenceNotes(
    VocalExercise exercise,
    PitchHighwayDifficulty difficulty,
  ) {
    final spec = exercise.highwaySpec;
    if (spec == null) return const [];
    final multiplier = PitchHighwayTempo.multiplierFor(difficulty, spec.segments);
    final segments = PitchHighwayTempo.scaleSegments(spec.segments, multiplier);
    return _segmentsToNotes(segments);
  }

  List<ReferenceNote> _segmentsToNotes(List<PitchSegment> segments) {
    final notes = <ReferenceNote>[];
    for (final seg in segments) {
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
            startSec: stepStart / 1000.0 + _leadInSec,
            endSec: stepEnd / 1000.0 + _leadInSec,
            midi: midi,
            lyric: seg.label,
          ));
        }
      } else {
        notes.add(ReferenceNote(
          startSec: seg.startMs / 1000.0 + _leadInSec,
          endSec: seg.endMs / 1000.0 + _leadInSec,
          midi: seg.midiNote,
          lyric: seg.label,
        ));
      }
    }
    return notes;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    final midiValues = _notes.map((n) => n.midi).toList();
    final minMidi = midiValues.isNotEmpty ? (midiValues.reduce(math.min) - 4) : 48;
    final maxMidi = midiValues.isNotEmpty ? (midiValues.reduce(math.max) + 4) : 72;
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
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: PitchHighwayPainter(
                      notes: _notes,
                      pitchTail: widget.lastTake.frames,
                      time: _time,
                      pixelsPerSecond: 160,
                      playheadFraction: 0.45,
                      smoothingWindowSec: 0.12,
                      drawBackground: false,
                      showLivePitch: false,
                      showPlayheadLine: false,
                      midiMin: minMidi,
                      midiMax: maxMidi,
                      colors: colors,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: PitchContourPainter(
                      frames: widget.lastTake.frames,
                      time: _time,
                      pixelsPerSecond: 160,
                      playheadFraction: 0.45,
                      midiMin: minMidi,
                      midiMax: maxMidi,
                      glowColor: colors.goldAccent,
                      coreColor: colors.goldAccent,
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
              ],
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
