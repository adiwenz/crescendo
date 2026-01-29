import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Paints simple abstract patterns for banner placeholders.
class AbstractBannerPainter extends CustomPainter {
  final int styleId;
  final double intensity;

  const AbstractBannerPainter(this.styleId, {this.intensity = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(styleId);
    final bg = _palette(styleId);
    final paint = Paint()..style = PaintingStyle.fill;
    final factor = intensity.clamp(0.6, 1.4);
    paint.color = bg.withOpacity(0.75 * factor);
    canvas.drawRect(Offset.zero & size, paint);

    // Shapes
    final shapeCount = 5 + styleId % 4;
    for (var i = 0; i < shapeCount; i++) {
      final kind = (styleId + i) % 3;
      paint.color = bg.withOpacity((0.25 + 0.1 * (i % 3)) * factor);
      switch (kind) {
        case 0:
          final w = size.width * (0.15 + rnd.nextDouble() * 0.2);
          final h = size.height * (0.25 + rnd.nextDouble() * 0.3);
          final x = rnd.nextDouble() * (size.width - w);
          final y = rnd.nextDouble() * (size.height - h);
          final r = Radius.circular(12 + rnd.nextDouble() * 16);
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), r), paint);
          break;
        case 1:
          final r2 = size.width * (0.1 + rnd.nextDouble() * 0.2);
          final x2 = rnd.nextDouble() * size.width;
          final y2 = rnd.nextDouble() * size.height;
          canvas.drawCircle(Offset(x2, y2), r2, paint);
          break;
        case 2:
          final path = Path();
          final startX = rnd.nextDouble() * size.width;
          final startY = rnd.nextDouble() * size.height;
          path.moveTo(startX, startY);
          for (var j = 0; j < 4; j++) {
            final dx = rnd.nextDouble() * size.width * 0.3;
            final dy = rnd.nextDouble() * size.height * 0.3;
            path.quadraticBezierTo(
              startX + dx / 2,
              startY + dy / 2,
              startX + dx,
              startY + dy,
            );
          }
          paint.strokeWidth = 6;
          paint.style = PaintingStyle.stroke;
          canvas.drawPath(path, paint);
          paint.style = PaintingStyle.fill;
          break;
      }
    }
  }

  Color _palette(int id) {
    // Purple and blue gradient palette - variations of the theme colors
    const colors = [
      Color(0xFF8B5CF6), // Saturated purple (primary)
      Color(0xFF7C3AED), // Deeper purple
      Color(0xFF60A5FA), // Light blue (secondary)
      Color(0xFF3B82F6), // Medium blue
      Color(0xFFA78BFA), // Lighter purple
      Color(0xFF818CF8), // Periwinkle
      Color(0xFF6366F1), // Indigo-purple
      Color(0xFF4F46E5), // Deep indigo
    ];
    return colors[id % colors.length];
  }

  @override
  bool shouldRepaint(covariant AbstractBannerPainter oldDelegate) {
    return oldDelegate.styleId != styleId;
  }
}
