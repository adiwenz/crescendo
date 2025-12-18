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
    AppThemeColors? colors,
  })  : colors = colors ?? AppThemeColors.dark,
        super(repaint: time);

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
      ..color = colors.divider.withOpacity(colors.isDark ? 1 : 0.6)
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
    final noteColor = colors.isDark
        ? colors.textPrimary.withOpacity(0.55)
        : colors.goldAccent.withOpacity(0.55);
    final barHeight = 16.0;
    final radius = Radius.circular(barHeight);
    final currentNote = _noteAtTime(currentTime);
    final currentStatus = _statusForTime(currentTime);
    final smoothedMidi = _smoothedMidiAt(currentTime);

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
        ..color = colors.glow
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

  void _drawPitchTrail(Canvas canvas, Size size, double t, double playheadX) {
    if (pitchTail.isEmpty) return;
    const trailWindowSec = 3.0;
    const maxJumpPx = 60.0;
    const resampleStep = 0.016;
    const maxGapSec = 0.12;
    const baseAlpha = 0.25;

    final raw = <_PitchSample>[];
    double? lastY;
    for (final f in pitchTail) {
      if (f.time < t - trailWindowSec || f.time > t) continue;
      final midi = f.midi;
      if (midi == null) continue;
      if (f.voicedProb != null && f.voicedProb! < 0.6) continue;
      if (f.rms != null && f.rms! < 0.02) continue;
      final y = PitchMath.midiToY(
        midi: midi,
        height: size.height,
        midiMin: midiMin,
        midiMax: midiMax,
      );
      if (lastY != null && (y - lastY!).abs() > maxJumpPx) continue;
      lastY = y;
      raw.add(_PitchSample(time: f.time, y: y));
    }
    if (raw.length < 2) return;

    final median = _medianFilter(raw, window: 5);
    final smoothed = _emaFilter(median, alpha: 0.15);
    final resampled = _resample(smoothed, step: resampleStep, maxGap: maxGapSec);
    if (resampled.length < 2) return;

    for (var i = 1; i < resampled.length - 1; i++) {
      final prev = resampled[i - 1];
      final curr = resampled[i];
      final next = resampled[i + 1];
      if ((curr.time - prev.time) > maxGapSec || (next.time - curr.time) > maxGapSec) {
        continue;
      }
      final age = (t - curr.time).clamp(0.0, trailWindowSec);
      final fade = 1 - (age / trailWindowSec);
      final alpha = (baseAlpha * fade).clamp(0.0, baseAlpha);
      if (alpha <= 0) continue;
      final xPrev = playheadX + (prev.time - t) * pixelsPerSecond;
      final xCurr = playheadX + (curr.time - t) * pixelsPerSecond;
      final xNext = playheadX + (next.time - t) * pixelsPerSecond;
      final start = Offset((xPrev + xCurr) / 2, (prev.y + curr.y) / 2);
      final end = Offset((xCurr + xNext) / 2, (curr.y + next.y) / 2);
      if (end.dx < -16 || start.dx > size.width + 16) continue;
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = colors.textPrimary.withOpacity(alpha * 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      final corePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = colors.textPrimary.withOpacity(alpha);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(xCurr, curr.y, end.dx, end.dy);
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, corePaint);
    }
  }

  List<_PitchSample> _medianFilter(List<_PitchSample> samples, {int window = 5}) {
    final radius = window ~/ 2;
    final filtered = <_PitchSample>[];
    for (var i = 0; i < samples.length; i++) {
      final ys = <double>[];
      for (var j = i - radius; j <= i + radius; j++) {
        if (j < 0 || j >= samples.length) continue;
        ys.add(samples[j].y);
      }
      ys.sort();
      final mid = ys[ys.length ~/ 2];
      filtered.add(_PitchSample(time: samples[i].time, y: mid));
    }
    return filtered;
  }

  List<_PitchSample> _emaFilter(List<_PitchSample> samples, {double alpha = 0.15}) {
    if (samples.isEmpty) return samples;
    final filtered = <_PitchSample>[];
    var last = samples.first.y;
    filtered.add(samples.first);
    for (var i = 1; i < samples.length; i++) {
      final next = alpha * samples[i].y + (1 - alpha) * last;
      last = next;
      filtered.add(_PitchSample(time: samples[i].time, y: next));
    }
    return filtered;
  }

  List<_PitchSample> _resample(
    List<_PitchSample> samples, {
    double step = 0.016,
    double maxGap = 0.12,
  }) {
    final resampled = <_PitchSample>[];
    final start = samples.first.time;
    final end = samples.last.time;
    var target = start;
    var idx = 0;
    while (target <= end && idx < samples.length - 1) {
      while (idx < samples.length - 1 && samples[idx + 1].time < target) {
        idx += 1;
      }
      final a = samples[idx];
      final b = samples[idx + 1];
      final span = (b.time - a.time);
      if (span > maxGap) {
        target = b.time;
        idx += 1;
        continue;
      }
      final ratio = span <= 0 ? 0.0 : (target - a.time) / span;
      final y = a.y + (b.y - a.y) * ratio.clamp(0.0, 1.0);
      resampled.add(_PitchSample(time: target, y: y));
      target += step;
    }
    return resampled;
  }

  @override
  bool shouldRepaint(covariant PitchHighwayPainter oldDelegate) {
    return oldDelegate.notes != notes ||
        oldDelegate.pitchTail != pitchTail ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.playheadFraction != playheadFraction ||
        (oldDelegate.drawBackground ?? true) != (drawBackground ?? true) ||
        oldDelegate.smoothingWindowSec != smoothingWindowSec ||
        oldDelegate.showLivePitch != showLivePitch ||
        oldDelegate.showPlayheadLine != showPlayheadLine;
  }
}

class _PitchSample {
  final double time;
  final double y;

  const _PitchSample({required this.time, required this.y});
}
