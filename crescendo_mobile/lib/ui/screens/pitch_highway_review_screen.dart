import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/last_take.dart';
import '../../models/reference_note.dart';
import '../../models/vocal_exercise.dart';
import '../../services/audio_synth_service.dart';
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
  Ticker? _ticker;
  Duration? _lastTick;
  bool _playing = false;
  late final List<ReferenceNote> _notes;
  late final double _durationSec;

  @override
  void initState() {
    super.initState();
    _notes = _buildReferenceNotes(widget.exercise);
    final specDuration =
        _notes.isEmpty ? 0.0 : _notes.map((n) => n.endSec).fold(0.0, math.max);
    _durationSec = math.max(widget.lastTake.durationSec, specDuration) +
        AudioSynthService.tailSeconds;
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker?.dispose();
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
    _lastTick = null;
    _ticker?.start();
    await _playAudio();
    if (mounted) setState(() {});
  }

  Future<void> _stop() async {
    if (!_playing) return;
    _playing = false;
    _ticker?.stop();
    _lastTick = null;
    await _synth.stop();
    if (mounted) setState(() {});
  }

  Future<void> _playAudio() async {
    final audioPath = widget.lastTake.audioPath;
    if (audioPath != null && audioPath.isNotEmpty) {
      final file = File(audioPath);
      if (await file.exists()) {
        await _synth.playFile(audioPath);
        return;
      }
    }
    await _playReference();
  }

  Future<void> _playReference() async {
    if (_notes.isEmpty) return;
    final path = await _synth.renderReferenceNotes(_notes);
    await _synth.playFile(path);
  }

  List<ReferenceNote> _buildReferenceNotes(VocalExercise exercise) {
    final spec = exercise.highwaySpec;
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
            midi: midi,
            lyric: seg.label,
          ));
        }
      } else {
        notes.add(ReferenceNote(
          startSec: seg.startMs / 1000.0,
          endSec: seg.endMs / 1000.0,
          midi: seg.midiNote,
          lyric: seg.label,
        ));
      }
    }
    return notes;
  }

  @override
  Widget build(BuildContext context) {
    final midiValues = _notes.map((n) => n.midi).toList();
    final minMidi = midiValues.isNotEmpty ? (midiValues.reduce(math.min) - 4) : 48;
    final maxMidi = midiValues.isNotEmpty ? (midiValues.reduce(math.max) + 4) : 72;
    const bgGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFFFFF3E2),
        Color(0xFFFFEEF1),
        Color(0xFFFFEAF6),
      ],
    );
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Review last take'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: bgGradient),
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
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PlayheadPainter(playheadFraction: 0.45),
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

  const _PlayheadPainter({required this.playheadFraction});

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * playheadFraction;
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.08)
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(x + 0.5, 0), Offset(x + 0.5, size.height), shadowPaint);
    final playheadPaint = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), playheadPaint);
  }

  @override
  bool shouldRepaint(covariant _PlayheadPainter oldDelegate) {
    return oldDelegate.playheadFraction != playheadFraction;
  }
}
