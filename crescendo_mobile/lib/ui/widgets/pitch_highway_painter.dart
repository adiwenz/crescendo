import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/pitch_frame.dart';
import '../../models/reference_note.dart';

enum PitchMatch { good, near, off }

class PitchHighwayPainter extends CustomPainter {
  final List<ReferenceNote> notes;
  final List<PitchFrame> pitchTail;
  final ValueListenable<double> time;
  final double pixelsPerSecond;
  final double playheadFraction;
  final double tailWindowSec;
  final int midiMin;
  final int midiMax;

  PitchHighwayPainter({
    required this.notes,
    required this.pitchTail,
    required this.time,
    this.pixelsPerSecond = 160,
    this.playheadFraction = 0.45,
    this.tailWindowSec = 4.0,
    this.midiMin = 48,
    this.midiMax = 72,
  }) : super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) {
    final currentTime = time.value;
    final bg = Paint()..color = const Color(0xFF4020B8);
    canvas.drawRect(Offset.zero & size, bg);

    final playheadX = size.width * playheadFraction;
    final noteColor = Colors.white.withOpacity(0.45);
    final highlightColor = Colors.white.withOpacity(0.8);
    final barHeight = 16.0;
    final radius = Radius.circular(barHeight);
    final currentNote = _noteAtTime(currentTime);

    for (final n in notes) {
      final startX = playheadX + (n.startSec - currentTime) * pixelsPerSecond;
      final endX = playheadX + (n.endSec - currentTime) * pixelsPerSecond;
      if (endX < -32 || startX > size.width + 32) continue;
      final y = _midiToY(n.midi.toDouble(), size.height);
      final rect = RRect.fromLTRBR(
        startX,
        y - barHeight / 2,
        endX,
        y + barHeight / 2,
        radius,
      );
      final paint = Paint()..color = identical(n, currentNote) ? highlightColor : noteColor;
      canvas.drawRRect(rect, paint);

      if (n.lyric != null && n.lyric!.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: n.lyric,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: math.max(0, endX - startX - 8));
        tp.paint(canvas, Offset(startX + 4, y - tp.height / 2));
      }
    }

    final tailFrames = pitchTail
        .where((f) => f.midi != null && f.time >= currentTime - tailWindowSec && f.time <= currentTime + 1)
        .toList();
    tailFrames.sort((a, b) => a.time.compareTo(b.time));
    final status = _statusForTime(currentTime);
    if (tailFrames.length > 1) {
      final path = Path();
      final offsets = tailFrames
          .map((f) => Offset(
                playheadX + (f.time - currentTime) * pixelsPerSecond,
                _midiToY(f.midi!, size.height),
              ))
          .toList();
      path.moveTo(offsets.first.dx, offsets.first.dy);
      for (var i = 1; i < offsets.length; i++) {
        path.lineTo(offsets[i].dx, offsets[i].dy);
      }

      final Color baseColor = switch (status) {
        PitchMatch.good => Colors.cyanAccent,
        PitchMatch.near => Colors.amberAccent,
        PitchMatch.off => Colors.pinkAccent,
      };
      for (var i = 0; i < 3; i++) {
        final paint = Paint()
          ..color = baseColor.withOpacity(0.5 - i * 0.15)
          ..strokeWidth = 8 - i * 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        canvas.drawPath(path, paint);
      }

      final head = offsets.last;
      canvas.drawCircle(head, 8, Paint()..color = baseColor);
      canvas.drawCircle(head, 16, Paint()..color = baseColor.withOpacity(0.2));
    }

    final playheadPaint = Paint()
      ..color = Colors.tealAccent
      ..strokeWidth = 3;
    canvas.drawLine(Offset(playheadX, 0), Offset(playheadX, size.height), playheadPaint);
  }

  ReferenceNote? _noteAtTime(double t) {
    for (final n in notes) {
      if (t >= n.startSec && t <= n.endSec) return n;
    }
    return null;
  }

  PitchMatch _statusForTime(double t) {
    final latest = pitchTail.isNotEmpty ? pitchTail.last : null;
    if (latest == null || latest.midi == null) return PitchMatch.off;
    final ref = _noteAtTime(t);
    if (ref == null) return PitchMatch.off;
    final cents = (latest.midi! - ref.midi) * 100;
    final absCents = cents.abs();
    if (absCents <= 25) return PitchMatch.good;
    if (absCents <= 60) return PitchMatch.near;
    return PitchMatch.off;
  }

  double _midiToY(double midi, double height) {
    final clamped = midi.clamp(midiMin.toDouble(), midiMax.toDouble());
    final ratio = (clamped - midiMin) / (midiMax - midiMin);
    return height - ratio * height;
  }

  @override
  bool shouldRepaint(covariant PitchHighwayPainter oldDelegate) {
    return oldDelegate.notes != notes ||
        oldDelegate.pitchTail != pitchTail ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.playheadFraction != playheadFraction;
  }
}
