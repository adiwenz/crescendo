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
  final double smoothingWindowSec;
  final int midiMin;
  final int midiMax;

  PitchHighwayPainter({
    required this.notes,
    required this.pitchTail,
    required this.time,
    this.pixelsPerSecond = 160,
    this.playheadFraction = 0.45,
    this.smoothingWindowSec = 0.2,
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
    final barHeight = 16.0;
    final radius = Radius.circular(barHeight);
    final currentNote = _noteAtTime(currentTime);
    final currentStatus = _statusForTime(currentTime);
    final smoothedMidi = _smoothedMidiAt(currentTime);

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
      final Color barColor;
      if (identical(n, currentNote)) {
        barColor = switch (currentStatus) {
          PitchMatch.good => Colors.cyanAccent.withOpacity(0.85),
          PitchMatch.near => Colors.amberAccent.withOpacity(0.85),
          PitchMatch.off => Colors.pinkAccent.withOpacity(0.85),
        };
      } else {
        barColor = noteColor;
      }
      final paint = Paint()..color = barColor;
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

    if (smoothedMidi != null) {
      const baseColor = Colors.cyanAccent;
      final y = _midiToY(smoothedMidi, size.height);
      final head = Offset(playheadX, y);
      canvas.drawCircle(head, 16, Paint()..color = baseColor.withOpacity(0.18));
      canvas.drawCircle(head, 10, Paint()..color = baseColor.withOpacity(0.35));
      canvas.drawCircle(head, 6, Paint()..color = baseColor);
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
    final latestMidi = _smoothedMidiAt(t);
    if (latestMidi == null) return PitchMatch.off;
    final ref = _noteAtTime(t);
    if (ref == null) return PitchMatch.off;
    final cents = (latestMidi - ref.midi) * 100;
    final absCents = cents.abs();
    if (absCents <= 25) return PitchMatch.good;
    if (absCents <= 60) return PitchMatch.near;
    return PitchMatch.off;
  }

  double? _smoothedMidiAt(double t) {
    if (pitchTail.isEmpty) return null;
    if (smoothingWindowSec <= 0) return _latestMidiAtOrBefore(t);
    final start = t - smoothingWindowSec;
    double weightedSum = 0;
    double totalWeight = 0;
    for (final f in pitchTail) {
      final midi = f.midi;
      if (midi == null || f.time < start || f.time > t) continue;
      final age = t - f.time;
      final weight = 1 - (age / smoothingWindowSec);
      final eased = weight * weight;
      weightedSum += midi * eased;
      totalWeight += eased;
    }
    if (totalWeight == 0) return _latestMidiAtOrBefore(t);
    return weightedSum / totalWeight;
  }

  double? _latestMidiAtOrBefore(double t) {
    for (var i = pitchTail.length - 1; i >= 0; i--) {
      final f = pitchTail[i];
      if (f.midi != null && f.time <= t) return f.midi;
    }
    return null;
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
        oldDelegate.playheadFraction != playheadFraction ||
        oldDelegate.smoothingWindowSec != smoothingWindowSec;
  }
}
