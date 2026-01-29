import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ProgressScoreRing extends StatelessWidget {
  final double? score;

  const ProgressScoreRing({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    final value = (score ?? 0).clamp(0.0, 100.0) / 100.0;
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 84,
          height: 84,
          child: CircularProgressIndicator(
            value: value,
            strokeWidth: 8,
            backgroundColor: colors.divider,
            valueColor: AlwaysStoppedAnimation<Color>(
              colors.accentPurple,
            ),
          ),
        ),
        Text(
          score == null ? '—' : score!.toStringAsFixed(0),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
        ),
      ],
    );
  }
}

class ProgressLineChart extends StatelessWidget {
  final List<double> values;
  final Color? lineColor;

  const ProgressLineChart({
    super.key,
    required this.values,
    this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    return CustomPaint(
      painter: _LineChartPainter(
        values: values,
        color: lineColor ?? colors.accentPurple,
        baselineColor: colors.divider.withOpacity(0.6),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class ProgressSparkline extends StatelessWidget {
  final List<double> values;
  final Color? color;

  const ProgressSparkline({
    super.key,
    required this.values,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    return CustomPaint(
      painter: _LineChartPainter(
        values: values,
        color: color ?? colors.accentPurple,
        baselineColor: Colors.transparent,
        showBaseline: false,
        strokeWidth: 2,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class ProgressBarChart extends StatelessWidget {
  final List<double> values;
  final Color? color;

  const ProgressBarChart({
    super.key,
    required this.values,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    return CustomPaint(
      painter: _BarChartPainter(
        values: values,
        color: color ?? colors.accentPurple,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final Color baselineColor;
  final bool showBaseline;
  final double strokeWidth;

  _LineChartPainter({
    required this.values,
    required this.color,
    required this.baselineColor,
    this.showBaseline = true,
    this.strokeWidth = 3,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final padding = 12.0;
    final chartWidth = size.width - padding * 2;
    final chartHeight = size.height - padding * 2;
    if (chartWidth <= 0 || chartHeight <= 0) return;

    if (showBaseline) {
      final baseline = Paint()
        ..color = baselineColor
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(padding, padding + chartHeight),
        Offset(padding + chartWidth, padding + chartHeight),
        baseline,
      );
    }

    if (values.isEmpty) return;

    final stepX = values.length == 1 ? 0 : chartWidth / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final v = values[i].clamp(0.0, 100.0) / 100.0;
      final x = padding + stepX * i;
      final y = padding + chartHeight * (1 - v);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.color != color ||
        oldDelegate.baselineColor != baselineColor ||
        oldDelegate.showBaseline != showBaseline ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class _BarChartPainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _BarChartPainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final padding = 8.0;
    final chartWidth = size.width - padding * 2;
    final chartHeight = size.height - padding * 2;
    final barCount = values.length;
    final barWidth = chartWidth / math.max(1, barCount * 1.5);
    final gap = barWidth * 0.5;
    final paint = Paint()..color = color;
    for (var i = 0; i < barCount; i++) {
      final v = values[i].clamp(0.0, 100.0) / 100.0;
      final barHeight = chartHeight * v;
      final x = padding + i * (barWidth + gap);
      final y = padding + chartHeight - barHeight;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(4),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}
