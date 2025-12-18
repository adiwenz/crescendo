import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/exercise_note_segment.dart';
import '../../models/vocal_exercise.dart';
import '../theme/app_theme.dart';

class ExercisePreviewMini extends StatelessWidget {
  final VocalExercise exercise;
  final double height;

  const ExercisePreviewMini({
    super.key,
    required this.exercise,
    this.height = 80,
  });

  @override
  Widget build(BuildContext context) {
    final segments = exercise.buildPreviewSegments();
    final totalDuration = exercise.highwaySpec?.totalMs ?? 0;
    final totalSec = totalDuration > 0 ? totalDuration / 1000.0 : _sumDuration(segments);
    final colors = AppThemeColors.of(context);
    final accent = colors.goldAccent.withOpacity(colors.isDark ? 0.85 : 0.9);
    return CustomPaint(
      painter: _ExercisePreviewPainter(
        segments: segments,
        totalDurationSec: totalSec,
        barColor: accent,
        lineColor: colors.isDark
            ? colors.textPrimary.withOpacity(0.35)
            : colors.divider.withOpacity(0.7),
        backgroundStart: Colors.transparent,
        backgroundEnd: Colors.transparent,
      ),
      child: SizedBox(height: height),
    );
  }

  double _sumDuration(List<ExerciseNoteSegment> segments) {
    if (segments.isEmpty) return 1.0;
    return segments
        .map((s) => s.startSec + s.durationSec)
        .reduce(math.max)
        .clamp(0.2, 60);
  }
}

class _ExercisePreviewPainter extends CustomPainter {
  final List<ExerciseNoteSegment> segments;
  final double totalDurationSec;
  final Color barColor;
  final Color lineColor;
  final Color backgroundStart;
  final Color backgroundEnd;

  _ExercisePreviewPainter({
    required this.segments,
    required this.totalDurationSec,
    required this.barColor,
    required this.lineColor,
    required this.backgroundStart,
    required this.backgroundEnd,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [backgroundStart, backgroundEnd],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    final lineX = size.width * 0.55;
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(lineX, 8), Offset(lineX, size.height - 8), linePaint);

    if (segments.isEmpty) {
      final placeholder = Paint()..color = barColor.withOpacity(0.35);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width * 0.5, size.height * 0.55),
          width: size.width * 0.45,
          height: 8,
        ),
        const Radius.circular(999),
      );
      canvas.drawRRect(rect, placeholder);
      return;
    }

    final minMidi = segments.map((s) => s.midi).reduce(math.min) - 1;
    final maxMidi = segments.map((s) => s.midi).reduce(math.max) + 1;
    final midiSpan = math.max(1, maxMidi - minMidi);
    final barHeight = 10.0;
    final paint = Paint()..color = barColor;
    final avgDur =
        segments.map((s) => s.durationSec).reduce((a, b) => a + b) / segments.length;
    final useDots = avgDur < 0.2;

    for (final seg in segments) {
      final start = seg.startSec / math.max(0.01, totalDurationSec);
      final dur = seg.durationSec / math.max(0.01, totalDurationSec);
      final midiNorm = (seg.midi - minMidi) / midiSpan;
      final y = 6 + (1 - midiNorm) * (size.height - barHeight - 12);
      final baseX = start * size.width;
      final maxWidth = math.max(barHeight, size.width);
      final barWidth =
          useDots ? barHeight : (dur * size.width).clamp(barHeight, maxWidth);
      final maxLeft = math.max(0.0, size.width - barWidth);
      final left = (baseX - (useDots ? barWidth / 2 : 0)).clamp(0.0, maxLeft);
      if (useDots) {
        canvas.drawCircle(
          Offset(left + barWidth / 2, y + barHeight / 2),
          barHeight / 2,
          paint,
        );
      } else {
        final rect = RRect.fromLTRBR(
          left,
          y,
          left + barWidth,
          y + barHeight,
          const Radius.circular(999),
        );
        canvas.drawRRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ExercisePreviewPainter oldDelegate) {
    return oldDelegate.segments != segments ||
        oldDelegate.totalDurationSec != totalDurationSec ||
        oldDelegate.barColor != barColor ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.backgroundStart != backgroundStart ||
        oldDelegate.backgroundEnd != backgroundEnd;
  }
}
