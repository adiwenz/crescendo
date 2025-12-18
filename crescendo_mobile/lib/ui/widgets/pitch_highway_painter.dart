import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/pitch_frame.dart';
import '../../models/reference_note.dart';
import '../../utils/pitch_math.dart';
import '../theme/app_theme.dart';

enum PitchMatch { good, near, off }

class PitchHighwayPainter extends CustomPainter {
  final List<ReferenceNote> notes;
  final List<PitchFrame> pitchTail;
  final ValueListenable<double> time;
  final double pixelsPerSecond;
  final double playheadFraction;
  final double smoothingWindowSec;
  final bool? drawBackground;
  final bool showLivePitch;
  final bool showPlayheadLine;
  final int midiMin;
  final int midiMax;
  final AppThemeColors colors;
  final ValueListenable<double?>? liveMidi;
  final double pitchTailTimeOffsetSec;

  PitchHighwayPainter({
    required this.notes,
    required this.pitchTail,
    required this.time,
    this.pixelsPerSecond = 160,
    this.playheadFraction = 0.45,
    this.smoothingWindowSec = 0.2,
    this.drawBackground = true,
    this.showLivePitch = true,
    this.showPlayheadLine = true,
    this.midiMin = 48,
    this.midiMax = 72,
    this.liveMidi,
    this.pitchTailTimeOffsetSec = 0,
    AppThemeColors? colors,
  })  : colors = colors ?? AppThemeColors.dark,
        super(repaint: liveMidi == null ? time : Listenable.merge([time, liveMidi]));

  @override
  void paint(Canvas canvas, Size size) {
    final currentTime = time.value;
    if (drawBackground ?? true) {
      final bg = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.bgTop,
            colors.bgBottom,
          ],
        ).createShader(Offset.zero & size);
      canvas.drawRect(Offset.zero & size, bg);
    }

    final gridPaint = Paint()
      ..color = colors.divider.withOpacity(colors.isMagical ? 0.18 : (colors.isDark ? 1 : 0.6))
      ..strokeWidth = 1;
    final gridStep = math.max(1, (midiMax - midiMin) ~/ 6);
    for (var midi = midiMin; midi <= midiMax; midi += gridStep) {
      final y = PitchMath.midiToY(
        midi: midi.toDouble(),
        height: size.height,
        midiMin: midiMin,
        midiMax: midiMax,
      );
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final playheadX = size.width * playheadFraction;
    final noteColor = colors.isMagical
        ? colors.goldAccent.withOpacity(0.65)
        : (colors.isDark
            ? colors.textPrimary.withOpacity(0.55)
            : colors.goldAccent.withOpacity(0.55));
    final barHeight = 16.0;
    final radius = Radius.circular(barHeight);
    final currentNote = _noteAtTime(currentTime);
    final smoothedMidi = liveMidi?.value ?? _smoothedMidiAt(currentTime);
    final currentStatus = _statusForTime(currentTime, smoothedMidi);

    for (final n in notes) {
      final startX = playheadX + (n.startSec - currentTime) * pixelsPerSecond;
      final endX = playheadX + (n.endSec - currentTime) * pixelsPerSecond;
      if (endX < -32 || startX > size.width + 32) continue;
      final y = PitchMath.midiToY(
        midi: n.midi.toDouble(),
        height: size.height,
        midiMin: midiMin,
        midiMax: midiMax,
      );
      final rect = RRect.fromLTRBR(
        startX,
        y - barHeight / 2,
        endX,
        y + barHeight / 2,
        radius,
      );
      final Color barColor;
      if (identical(n, currentNote)) {
        if (colors.isDark) {
          barColor = switch (currentStatus) {
            PitchMatch.good => colors.textPrimary.withOpacity(0.95),
            PitchMatch.near => colors.textPrimary.withOpacity(0.8),
            PitchMatch.off => colors.textPrimary.withOpacity(0.6),
          };
        } else {
          barColor = switch (currentStatus) {
            PitchMatch.good => colors.goldAccent.withOpacity(0.95),
            PitchMatch.near => colors.goldAccent.withOpacity(0.75),
            PitchMatch.off => colors.goldAccent.withOpacity(0.55),
          };
        }
      } else {
        barColor = noteColor;
      }
      final glowPaint = Paint()
        ..color = (colors.isMagical ? colors.lavenderGlow : colors.glow)
            .withOpacity(colors.isMagical ? 0.4 : 1)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      final paint = Paint()..color = barColor;
      canvas.drawRRect(rect, glowPaint);
      canvas.drawRRect(rect, paint);

      if (n.lyric != null && n.lyric!.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: n.lyric,
            style: TextStyle(color: colors.textPrimary, fontSize: 12),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: math.max(0, endX - startX - 8));
        tp.paint(canvas, Offset(startX + 4, y - tp.height / 2));
      }
    }

    if (showLivePitch) {
      _drawPitchTrail(canvas, size, currentTime, playheadX);

      if (smoothedMidi != null) {
        assert(() {
          if (pitchTail.isNotEmpty) {
            final tailMidi = pitchTail.last.midi;
            if (tailMidi != null) {
              final tailY = PitchMath.midiToY(
                midi: tailMidi,
                height: size.height,
                midiMin: midiMin,
                midiMax: midiMax,
              );
              final ballY = PitchMath.midiToY(
                midi: smoothedMidi,
                height: size.height,
                midiMin: midiMin,
                midiMax: midiMax,
              );
              return (tailY - ballY).abs() < 0.1;
            }
          }
          return true;
        }());
        final y = PitchMath.midiToY(
          midi: smoothedMidi,
          height: size.height,
          midiMin: midiMin,
          midiMax: midiMax,
        );
        final head = Offset(playheadX, y);
        canvas.drawCircle(
          head,
          16,
          Paint()
            ..color = colors.glow
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
        );
        canvas.drawCircle(
          head,
          10,
          Paint()
            ..color = colors.textPrimary.withOpacity(0.5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        canvas.drawCircle(head, 7, Paint()..color = colors.textPrimary);
      }
    }

    if (showPlayheadLine) {
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.3)
        ..strokeWidth = 2.0;
      canvas.drawLine(
        Offset(playheadX + 0.5, 0),
        Offset(playheadX + 0.5, size.height),
        shadowPaint,
      );
      final playheadPaint = Paint()
        ..color = colors.blueAccent.withOpacity(0.7)
        ..strokeWidth = 2.0;
      canvas.drawLine(Offset(playheadX, 0), Offset(playheadX, size.height), playheadPaint);
    }
  }

  ReferenceNote? _noteAtTime(double t) {
    for (final n in notes) {
      if (t >= n.startSec && t <= n.endSec) return n;
    }
    return null;
  }

  PitchMatch _statusForTime(double t, double? latestMidi) {
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

  void _drawPitchTrail(Canvas canvas, Size size, double t, double playheadX) {
    if (pitchTail.isEmpty) return;
    final tAdjusted = t + pitchTailTimeOffsetSec;
    const trailWindowSec = 3.0;
    const maxJumpPx = 60.0;
    const maxGapSec = 0.12;
    const baseAlpha = 0.25;

    final raw = <_PitchSample>[];
    double? lastY;
    for (final f in pitchTail) {
      if (f.time < tAdjusted - trailWindowSec || f.time > tAdjusted) continue;
      final midi = f.midi;
      if (midi == null) continue;
      final y = PitchMath.midiToY(
        midi: midi,
        height: size.height,
        midiMin: midiMin,
        midiMax: midiMax,
      );
      if (lastY != null && (y - lastY!).abs() > maxJumpPx) continue;
      lastY = y;
      final voiced = (f.voicedProb ?? 1.0) >= 0.6 && (f.rms ?? 1.0) >= 0.02;
      raw.add(_PitchSample(time: f.time, y: y, voiced: voiced));
    }
    if (raw.length < 2) {
      final live = liveMidi?.value;
      if (live == null) return;
      final y = PitchMath.midiToY(
        midi: live,
        height: size.height,
        midiMin: midiMin,
        midiMax: midiMax,
      );
      final shortTrailSec = 0.2;
      final startX = playheadX + (-shortTrailSec) * pixelsPerSecond;
      final endX = playheadX;
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = colors.textPrimary.withOpacity(0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      final corePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = colors.textPrimary.withOpacity(0.35);
      final path = Path()
        ..moveTo(startX, y)
        ..lineTo(endX, y);
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, corePaint);
      return;
    }

    if (raw.length < 2) return;

    for (var i = 1; i < raw.length; i++) {
      final prev = raw[i - 1];
      final curr = raw[i];
      if ((curr.time - prev.time) > maxGapSec) continue;
      final age = (tAdjusted - curr.time).clamp(0.0, trailWindowSec);
      final fade = 1 - (age / trailWindowSec);
      final base = (baseAlpha * fade).clamp(0.0, baseAlpha);
      if (base <= 0) continue;
      final voicedFactor = curr.voiced ? 1.0 : 0.35;
      final alpha = (base * voicedFactor).clamp(0.0, baseAlpha);
      final xPrev = playheadX + (prev.time - tAdjusted) * pixelsPerSecond;
      final xCurr = playheadX + (curr.time - tAdjusted) * pixelsPerSecond;
      if (xCurr < -16 || xPrev > size.width + 16) continue;
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = colors.textPrimary.withOpacity(alpha * 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      final corePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = colors.textPrimary.withOpacity(alpha);
      canvas.drawLine(Offset(xPrev, prev.y), Offset(xCurr, curr.y), glowPaint);
      canvas.drawLine(Offset(xPrev, prev.y), Offset(xCurr, curr.y), corePaint);
    }
  }

  @override
  bool shouldRepaint(covariant PitchHighwayPainter oldDelegate) {
    return oldDelegate.notes != notes ||
        oldDelegate.pitchTail != pitchTail ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.playheadFraction != playheadFraction ||
        (oldDelegate.drawBackground ?? true) != (drawBackground ?? true) ||
        oldDelegate.smoothingWindowSec != smoothingWindowSec ||
        oldDelegate.pitchTailTimeOffsetSec != pitchTailTimeOffsetSec ||
        oldDelegate.showLivePitch != showLivePitch ||
        oldDelegate.showPlayheadLine != showPlayheadLine;
  }
}

class _PitchSample {
  final double time;
  final double y;
  final bool voiced;

  const _PitchSample({
    required this.time,
    required this.y,
    required this.voiced,
  });
}
