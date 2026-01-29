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
        // Main gradient background
        Container(
          decoration: BoxDecoration(
            gradient: colors.backgroundGradient,
          ),
        ),
        // Subtle wave overlay
        Positioned.fill(
          child: CustomPaint(
            painter: _WaveOverlayPainter(colors: colors),
          ),
        ),
        // Bokeh circles (very low opacity)
        Positioned.fill(
          child: CustomPaint(
            painter: _BokehPainter(colors: colors),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _WaveOverlayPainter extends CustomPainter {
  final AppThemeColors colors;

  const _WaveOverlayPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    // Subtle wave shapes with very low opacity
    final paint1 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colors.accentBlue.withOpacity(0.08),
          colors.accentPurple.withOpacity(0.06),
        ],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final paint2 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          colors.accentPurple.withOpacity(0.06),
          colors.accentBlue.withOpacity(0.08),
        ],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Wave 1
    final path1 = Path()
      ..moveTo(0, size.height * 0.4)
      ..quadraticBezierTo(size.width * 0.3, size.height * 0.3, size.width * 0.55,
          size.height * 0.55)
      ..quadraticBezierTo(
          size.width * 0.75, size.height * 0.7, size.width, size.height * 0.55)
      ..lineTo(size.width, 0)
      ..lineTo(0, 0);

    // Wave 2
    final path2 = Path()
      ..moveTo(0, size.height * 0.65)
      ..quadraticBezierTo(size.width * 0.25, size.height * 0.8,
          size.width * 0.55, size.height * 0.7)
      ..quadraticBezierTo(
          size.width * 0.8, size.height * 0.55, size.width, size.height * 0.7)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height);

    canvas.drawPath(path1, paint1);
    canvas.drawPath(path2, paint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BokehPainter extends CustomPainter {
  final AppThemeColors colors;

  const _BokehPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final rand = Random(42);
    // Very subtle bokeh circles
    final circleCount = (size.width * size.height / 15000).clamp(8, 20).toInt();
    final paint = Paint()
      ..color = colors.accentPurple.withOpacity(0.04)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < circleCount; i++) {
      final dx = rand.nextDouble() * size.width;
      final dy = rand.nextDouble() * size.height;
      final r = rand.nextDouble() * 40 + 20; // 20-60 radius
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }

    // A few smaller circles
    final smallPaint = Paint()
      ..color = colors.accentBlue.withOpacity(0.03)
      ..style = PaintingStyle.fill;
    for (var i = 0; i < circleCount ~/ 2; i++) {
      final dx = rand.nextDouble() * size.width;
      final dy = rand.nextDouble() * size.height;
      final r = rand.nextDouble() * 15 + 10; // 10-25 radius
      canvas.drawCircle(Offset(dx, dy), r, smallPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
