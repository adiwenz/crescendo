import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../../../design/app_colors.dart';

// SCREEN 1: Welcome - Rising Curve
class WelcomeVisual extends StatefulWidget {
  const WelcomeVisual({super.key});

  @override
  State<WelcomeVisual> createState() => _WelcomeVisualState();
}

class _WelcomeVisualState extends State<WelcomeVisual> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _RisingCurvePainter(_controller.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class _RisingCurvePainter extends CustomPainter {
  final double progress;
  _RisingCurvePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final path = Path();
    // Move mostly to bottom: 0.8 -> 0.7 range
    path.moveTo(0, size.height * 0.8);
    
    // Abstract rising curve
    path.cubicTo(
      size.width * 0.3, size.height * 0.8,
      size.width * 0.5, size.height * 0.75 + (progress * 20),
      size.width, size.height * 0.6,
    );

    canvas.drawPath(path, paint);
    
    // Glow effect
    final glowPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      
    canvas.drawPath(path, glowPaint);
  }

  @override
  bool shouldRepaint(_RisingCurvePainter oldDelegate) => oldDelegate.progress != progress;
}

// SCREEN 2: Why Exercises Help - Bullet Points & Layers
class WhyVisual extends StatelessWidget {
  const WhyVisual({super.key});

  @override
  Widget build(BuildContext context) {
     // Placeholder for "layered pitch-like lines"
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _LayeredLinesPainter(),
          ),
        ),
        // Floating bullets could be actual widgets animated in the parent screen
      ],
    );
  }
}

class _LayeredLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (int i = 0; i < 3; i++) {
      paint.color = Colors.white.withOpacity(0.2 + (i * 0.1));
      final path = Path();
      // Move to bottom: 0.7 range
      double y = size.height * 0.7 + (i * 30);
      path.moveTo(0, y);
      path.quadraticBezierTo(size.width * 0.5, y - 20, size.width, y);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// SCREEN 3: How It Works - Multiple Glowing Swoops (Static)
class HowItWorksVisual extends StatelessWidget {
  const HowItWorksVisual({super.key});

  @override
  Widget build(BuildContext context) {
    // Static frame (progress = 0.0 or a nice offset like 0.25)
    // Let's use 0.25 to catch some curve variation
    return CustomPaint(
      painter: _GlowingSwoopsPainter(0.25),
      size: Size.infinite,
    );
  }
}

class _GlowingSwoopsPainter extends CustomPainter {
  final double progress;
  _GlowingSwoopsPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    // We want multiple lines "swooping" and intersecting gracefully
    final count = 4;
    
    for (int i = 0; i < count; i++) {
      // Phase shift for each line so they don't move firmly together
      double phase = (i * 0.5) + (progress * 2 * math.pi);
      
      // Base opacity varies by line index
      double opacity = 0.3 + (i * 0.15);
      if (opacity > 1.0) opacity = 1.0;

      // GLOW PAINT (Thick, blurred)
      final glowPaint = Paint()
        ..color = Colors.white.withOpacity(opacity * 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

      // MAIN LINE PAINT (Thin, sharp)
      final linePaint = Paint()
        ..color = Colors.white.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
        
      final path = Path();
      
      // Start point varies slightly
      double startY = size.height * 0.65 + (math.sin(phase) * 20);
      path.moveTo(0, startY);
      
      // Control points for cubic bezier
      // CP1
      double cp1x = size.width * 0.3;
      double cp1y = size.height * 0.55 + (math.cos(phase * 0.7) * 60);
      
      // CP2
      double cp2x = size.width * 0.7;
      double cp2y = size.height * 0.75 + (math.sin(phase * 0.9) * 60);
      
      // End Point
      double endY = size.height * 0.60 + (math.cos(phase) * 20);
      
      path.cubicTo(cp1x, cp1y, cp2x, cp2y, size.width, endY);
      
      // Draw Glow
      canvas.drawPath(path, glowPaint);
      // Draw Line
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(_GlowingSwoopsPainter oldDelegate) => false;
}

// SCREEN 4: Get Started - Opening Arc
class GetStartedVisual extends StatelessWidget {
  const GetStartedVisual({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OpeningArcPainter(),
      size: Size.infinite,
    );
  }
}

class _OpeningArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.white.withOpacity(0), Colors.white.withOpacity(0.8), Colors.white.withOpacity(0)],
        stops: const [0.0, 0.5, 1.0]
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    final path = Path();
    // Move to bottom: 0.8->0.6 range
    path.moveTo(0, size.height * 0.8);
    path.quadraticBezierTo(size.width * 0.5, size.height * 0.6, size.width, size.height * 0.75);
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
