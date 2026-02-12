import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../theme/ballad_theme.dart';

class CentsMeter extends StatelessWidget {
  final double? cents;
  final double confidence;

  const CentsMeter({
    super.key,
    required this.cents,
    required this.confidence,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = cents != null;
    final target = (cents ?? 0).clamp(-50.0, 50.0).toDouble();
    final activeColor = confidence >= 0.5 ? BalladTheme.accentTeal : BalladTheme.textSecondary;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      builder: (context, value, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 48,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final centerX = width / 2;
                  final x = centerX + (value / 50.0) * (width / 2);
                  return Stack(
                    children: [
                      CustomPaint(
                        size: Size(width, 48),
                        painter: _CentsMeterPainter(color: activeColor.withOpacity(0.7)),
                      ),
                      Positioned(
                        left: math.max(0, math.min(width - 14, x - 7)),
                        top: 10,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: activeColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: activeColor.withOpacity(0.35),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasValue ? '${value >= 0 ? '+' : ''}${value.toStringAsFixed(0)}¢' : '—',
              textAlign: TextAlign.center,
              style: BalladTheme.titleMedium,
            ),
          ],
        );
      },
    );
  }
}

class _CentsMeterPainter extends CustomPainter {
  final Color color;

  _CentsMeterPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final track = Paint()
      ..color = Colors.white10
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), track);

    final tickPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.5;
    final zeroPaint = Paint()
      ..color = color
      ..strokeWidth = 2.5;

    for (var c = -50; c <= 50; c += 10) {
      final x = ((c + 50) / 100) * size.width;
      final isZero = c == 0;
      final tickHeight = isZero ? 14.0 : 8.0;
      canvas.drawLine(
        Offset(x, centerY - tickHeight / 2),
        Offset(x, centerY + tickHeight / 2),
        isZero ? zeroPaint : tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CentsMeterPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
