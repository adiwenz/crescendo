import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/replay_models.dart';

class PitchSnapshotChart extends StatelessWidget {
  final List<TargetNote> targetNotes;
  final List<PitchSample> recordedSamples;
  final int durationMs;
  final double height;

  const PitchSnapshotChart({
    super.key,
    required this.targetNotes,
    required this.recordedSamples,
    required this.durationMs,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final minMax = _computeViewport(targetNotes, recordedSamples);
          return CustomPaint(
            painter: _SnapshotPainter(
              notes: targetNotes,
              samples: recordedSamples,
              durationMs: durationMs,
              minMidi: minMax.$1,
              maxMidi: minMax.$2,
              width: width,
              height: height,
            ),
          );
        },
      ),
    );
  }
}

class _SnapshotPainter extends CustomPainter {
  final List<TargetNote> notes;
  final List<PitchSample> samples;
  final int durationMs;
  final double minMidi;
  final double maxMidi;
  final double width;
  final double height;

  _SnapshotPainter({
    required this.notes,
    required this.samples,
    required this.durationMs,
    required this.minMidi,
    required this.maxMidi,
    required this.width,
    required this.height,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE6EEF3)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final midi = minMidi + (maxMidi - minMidi) * (i / 4);
      final y = _midiToY(midi, minMidi, maxMidi, size.height, 8, 8);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final path = Path();
    bool started = false;
    for (final s in _validSamples(samples)) {
      final x = _timeToX(s.timeMs, durationMs, size.width);
      final y = _midiToY(s.midi!, minMidi, maxMidi, size.height, 8, 8);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    final contourPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFFFB347);
    canvas.drawPath(path, contourPaint);

    final notePaint = Paint()..color = const Color(0xFFFFC978);
    const barHeight = 14.0;
    for (final n in notes) {
      final x = _timeToX(n.startMs, durationMs, size.width);
      final y = _midiToY(n.midi, minMidi, maxMidi, size.height, 8, 8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y), width: 36, height: barHeight),
          const Radius.circular(7),
        ),
        notePaint,
      );
    }
  }

  List<PitchSample> _validSamples(List<PitchSample> samples) {
    return samples.where((s) {
      final midi = s.midi ?? _hzToMidi(s.freqHz);
      return midi != null && midi.isFinite;
    }).map((s) {
      final midi = s.midi ?? _hzToMidi(s.freqHz);
      return PitchSample(timeMs: s.timeMs, midi: midi);
    }).toList();
  }

  double? _hzToMidi(double? hz) {
    if (hz == null || hz <= 0 || hz.isNaN || hz.isInfinite) return null;
    return 69 + 12 * (math.log(hz / 440.0) / math.ln2);
  }

  @override
  bool shouldRepaint(covariant _SnapshotPainter oldDelegate) {
    return oldDelegate.notes != notes ||
        oldDelegate.samples != samples ||
        oldDelegate.durationMs != durationMs ||
        oldDelegate.minMidi != minMidi ||
        oldDelegate.maxMidi != maxMidi;
  }
}

(double, double) _computeViewport(
  List<TargetNote> notes,
  List<PitchSample> samples,
) {
  final noteMidis = notes.map((n) => n.midi).toList();
  final sampleMidis = samples
      .map((s) => s.midi ?? _hzToMidiStatic(s.freqHz))
      .whereType<double>()
      .toList();
  final source = noteMidis.isNotEmpty ? noteMidis : sampleMidis;
  if (source.isEmpty) return (48, 72);
  final min = source.reduce(math.min) - 3;
  final max = source.reduce(math.max) + 3;
  return (min, max);
}

double _midiToY(
  double midi,
  double minMidi,
  double maxMidi,
  double height,
  double topPad,
  double bottomPad,
) {
  final clamped = midi.clamp(minMidi, maxMidi);
  final usableHeight = (height - topPad - bottomPad).clamp(1.0, height);
  final ratio = (clamped - minMidi) / (maxMidi - minMidi);
  return (height - bottomPad) - ratio * usableHeight;
}

double _timeToX(int timeMs, int durationMs, double width) {
  if (durationMs <= 0) return 0;
  final clamped = timeMs.clamp(0, durationMs).toDouble();
  return (clamped / durationMs) * width;
}

double? _hzToMidiStatic(double? hz) {
  if (hz == null || hz <= 0 || hz.isNaN || hz.isInfinite) return null;
  return 69 + 12 * (math.log(hz / 440.0) / math.ln2);
}
