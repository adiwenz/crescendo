import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.bgTop, AppColors.bgBottom],
            ),
          ),
        ),
        const Positioned.fill(child: CustomPaint(painter: _StarFieldPainter())),
        if (showWave)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(height: 140, child: CustomPaint(painter: _WavePainter())),
          ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _StarFieldPainter extends CustomPainter {
  const _StarFieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rand = Random(42);
    final dotCount = (size.width * size.height / 9000).clamp(60, 160).toInt();
    final paint = Paint()..color = Colors.white.withOpacity(0.06);
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
  const _WavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.06)
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
