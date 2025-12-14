import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/pitch_frame.dart';
import '../../models/warmup.dart';

class PitchGraph extends StatelessWidget {
  final List<PitchFrame> frames;
  final List<NoteSegment> reference;
  final double playheadTime;
  final bool showHz;
  final bool showDots;

  const PitchGraph({
    super.key,
    required this.frames,
    required this.reference,
    required this.playheadTime,
    this.showHz = false,
    this.showDots = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _PitchPainter(frames, reference, playheadTime, showHz: showHz, showDots: showDots),
        );
      },
    );
  }
}

class _PitchPainter extends CustomPainter {
  final List<PitchFrame> frames;
  final List<NoteSegment> reference;
  final double playheadTime;
  final bool showHz;
  final bool showDots;

  _PitchPainter(this.frames, this.reference, this.playheadTime, {required this.showHz, required this.showDots});

  @override
  void paint(Canvas canvas, Size size) {
    if (frames.isEmpty) return;
    final times = frames.map((f) => f.time).toList();
    final minT = times.first;
    final maxT = times.last;
    final midiVals = frames.map((f) => f.midi ?? 0).where((v) => v > 0).toList();
    if (midiVals.isEmpty) return;
    final minM = midiVals.reduce(math.min) - 2;
    final maxM = midiVals.reduce(math.max) + 2;
    double xForTime(double t) => ((t - minT) / (maxT - minT + 1e-6)) * size.width;
    double yForPitch(double m) => size.height - ((m - minM) / (maxM - minM + 1e-6)) * size.height;

    final refPaint = Paint()..color = Colors.amber.withOpacity(0.35);
    for (final seg in reference) {
      final left = xForTime(seg.start);
      final right = xForTime(seg.end);
      final top = yForPitch(seg.targetMidi + 0.3);
      final bottom = yForPitch(seg.targetMidi - 0.3);
      final rect = Rect.fromLTRB(left, top, right, bottom);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), refPaint);
    }

    final path = Path();
    bool started = false;
    for (final f in frames) {
      if (f.midi == null) continue;
      final x = xForTime(f.time);
      final y = yForPitch(f.midi!);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.blue;
    canvas.drawPath(path, linePaint);

    if (showDots) {
      for (final f in frames) {
        if (f.midi == null) continue;
        final x = xForTime(f.time);
        final y = yForPitch(f.midi!);
        final c = f.centsError == null
            ? Colors.grey
            : (f.centsError!.abs() <= 20
                ? Colors.green
                : (f.centsError!.abs() <= 50 ? Colors.yellow.shade700 : Colors.red));
        canvas.drawCircle(Offset(x, y), 2.5, Paint()..color = c);
      }
    }

    final playX = xForTime(playheadTime);
    final playPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    canvas.drawLine(Offset(playX, 0), Offset(playX, size.height), playPaint);
  }

  @override
  bool shouldRepaint(covariant _PitchPainter oldDelegate) {
    return oldDelegate.frames != frames || oldDelegate.playheadTime != playheadTime || oldDelegate.showHz != showHz;
  }
}
