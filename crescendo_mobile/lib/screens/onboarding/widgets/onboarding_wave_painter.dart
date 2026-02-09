import 'package:flutter/material.dart';

class OnboardingWavePainter extends CustomPainter {
  final Color color;
  OnboardingWavePainter({this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    // Layer 1: Main Wave
    final paint1 = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    final path1 = Path();
    path1.moveTo(0, size.height * 0.80);
    path1.cubicTo(
      size.width * 0.3, size.height * 0.75, // Control point 1
      size.width * 0.6, size.height * 0.85, // Control point 2
      size.width, size.height * 0.75,       // End point
    );
    path1.lineTo(size.width, size.height);
    path1.lineTo(0, size.height);
    path1.close();
    canvas.drawPath(path1, paint1);

    // Layer 2: Subtle Secondary Wave (Behind/Intersecting)
    final paint2 = Paint()
      ..color = color.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    final path2 = Path();
    path2.moveTo(0, size.height * 0.85);
    path2.cubicTo(
      size.width * 0.4, size.height * 0.90, 
      size.width * 0.7, size.height * 0.78, 
      size.width, size.height * 0.82,
    );
    path2.lineTo(size.width, size.height);
    path2.lineTo(0, size.height);
    path2.close();
    canvas.drawPath(path2, paint2);
    
    // Layer 3: Thin accent line on top of main wave
    final paintLine = Paint()
      ..color = color.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
      
    // Re-draw top of path1
    final pathLine = Path();
    pathLine.moveTo(0, size.height * 0.80);
    pathLine.cubicTo(
       size.width * 0.3, size.height * 0.75,
       size.width * 0.6, size.height * 0.85,
       size.width, size.height * 0.75,
    );
    canvas.drawPath(pathLine, paintLine);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
