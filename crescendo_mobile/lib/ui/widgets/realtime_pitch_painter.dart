import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/pitch_frame.dart';
import '../../services/pitch_estimator_service.dart';

class PitchTailPainter extends CustomPainter {
  final List<PitchFrame> frames;
  final double minMidi;
  final double maxMidi;

  PitchTailPainter({required this.frames, this.minMidi = 48, this.maxMidi = 84});

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFFEFF1F6);
    canvas.drawRect(Offset.zero & size, bg);

    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (frames.isEmpty) return;
    final voiced = frames.where((f) => f.hz != null).toList();
    if (voiced.isEmpty) return;

    double xForIndex(int idx) {
      final maxPts = frames.length;
      return size.width * (idx / math.max(1, maxPts - 1));
    }

    double yForHz(double hz) {
      final midi = PitchEstimatorService.hzToMidi(hz);
      final clamped = midi.clamp(minMidi, maxMidi);
      final norm = (clamped - minMidi) / (maxMidi - minMidi);
      return size.height * (1 - norm);
    }

    final path = Path();
    bool started = false;
    for (var i = 0; i < frames.length; i++) {
      final f = frames[i];
      if (f.hz == null) {
        started = false;
        continue;
      }
      final p = Offset(xForIndex(i), yForHz(f.hz!));
      if (!started) {
        path.moveTo(p.dx, p.dy);
        started = true;
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    final tailPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.blueAccent.withOpacity(0.8);
    canvas.drawPath(path, tailPaint);

    final last = frames.lastWhere((f) => f.hz != null, orElse: () => frames.last);
    if (last.hz != null) {
      final dot = Offset(xForIndex(frames.length - 1), yForHz(last.hz!));
      canvas.drawCircle(dot, 6, Paint()..color = Colors.blueAccent);
    }
  }

  @override
  bool shouldRepaint(covariant PitchTailPainter oldDelegate) {
    return oldDelegate.frames != frames;
  }
}
