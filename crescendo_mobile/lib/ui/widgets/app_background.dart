import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'magical_background.dart';

class AppBackground extends StatelessWidget {
  final Widget child;
  final bool showWave;

  const AppBackground({
    super.key,
    required this.child,
    this.showWave = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    if (colors.isMagical) {
      return MagicalBackground(child: child);
    }
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [colors.bgTop, colors.bgBottom],
            ),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _StarFieldPainter(isDark: colors.isDark),
          ),
        ),
        if (showWave)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(
              height: 140,
              child: CustomPaint(
                painter: _WavePainter(
                  start: colors.bgBottom,
                  end: colors.blueAccent,
                ),
              ),
            ),
          ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _StarFieldPainter extends CustomPainter {
  final bool isDark;

  const _StarFieldPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final rand = Random(42);
    final dotCount = isDark
        ? (size.width * size.height / 9000).clamp(60, 160).toInt()
        : (size.width * size.height / 12000).clamp(30, 80).toInt();
    final paint = Paint()
      ..color = isDark
          ? Colors.white.withOpacity(0.06)
          : const Color(0xFF7DBCD9).withOpacity(0.12);
    for (var i = 0; i < dotCount; i++) {
      final dx = rand.nextDouble() * size.width;
      final dy = rand.nextDouble() * size.height;
      final r = rand.nextDouble() * 1.6 + 0.4;
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WavePainter extends CustomPainter {
  final Color start;
  final Color end;

  const _WavePainter({required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [start.withOpacity(0.25), end.withOpacity(0.35)],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, size.height * 0.5)
      ..quadraticBezierTo(size.width * 0.25, size.height * 0.35,
          size.width * 0.5, size.height * 0.5)
      ..quadraticBezierTo(size.width * 0.75, size.height * 0.65,
          size.width, size.height * 0.5)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
