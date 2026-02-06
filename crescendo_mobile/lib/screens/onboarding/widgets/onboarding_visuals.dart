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

// SCREEN 3: How It Works - Stabilizing Line
class HowItWorksVisual extends StatefulWidget {
  const HowItWorksVisual({super.key});

  @override
  State<HowItWorksVisual> createState() => _HowItWorksVisualState();
}

class _HowItWorksVisualState extends State<HowItWorksVisual> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
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
          painter: _StabilizingLinePainter(_controller.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class _StabilizingLinePainter extends CustomPainter {
  final double progress;
  _StabilizingLinePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final path = Path();
    // Move to bottom: 0.7 range
    double midY = size.height * 0.7;
    
    path.moveTo(0, midY);
    
    // Line moves from wavy to straight
    for (double x = 0; x <= size.width; x+= 5) {
      double wave = math.sin((x / 50) + (progress * 2 * math.pi)) * 20;
      // Dampen wave as it goes right
      double dampen = 1.0 - (x / size.width); 
      // Or dampen based on time to show stabilization? 
      // Let's dampen based on X to show "process" of stabilizing
      path.lineTo(x, midY + (wave * dampen));
    }
    
    canvas.drawPath(path, paint);

    // Highlight at end
    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.fill;
  }

  @override
  bool shouldRepaint(_StabilizingLinePainter oldDelegate) => true;
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
