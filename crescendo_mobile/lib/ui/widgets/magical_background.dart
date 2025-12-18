import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/magical_tokens.dart';
import 'breathing.dart';
import 'glow.dart';

class MagicalBackground extends StatefulWidget {
  final Widget child;

  const MagicalBackground({super.key, required this.child});

  @override
  State<MagicalBackground> createState() => _MagicalBackgroundState();
}

class _MagicalBackgroundState extends State<MagicalBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Star> _stars;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    _stars = _buildStars(seed: 42);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                MagicalTokens.deepIndigo,
                MagicalTokens.violetFog,
              ],
            ),
          ),
        ),
        RepaintBoundary(
          child: CustomPaint(
            painter: _MagicalStarPainter(stars: _stars, animation: _controller),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _WavePainter(animation: _controller),
              child: const SizedBox(height: 150),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 26,
          child: Breathing(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: const [
                _GlowingNote(glyph: '♪'),
                _GlowingNote(glyph: '♫'),
                _GlowingNote(glyph: '♩'),
                _GlowingNote(glyph: '♪'),
              ],
            ),
          ),
        ),
        Positioned.fill(child: widget.child),
      ],
    );
  }

  List<_Star> _buildStars({required int seed}) {
    final rand = math.Random(seed);
    return List.generate(80, (index) {
      return _Star(
        offset: Offset(rand.nextDouble(), rand.nextDouble()),
        radius: rand.nextDouble() * 1.6 + 0.4,
        phase: rand.nextDouble() * math.pi * 2,
      );
    });
  }
}

class _GlowingNote extends StatelessWidget {
  final String glyph;

  const _GlowingNote({required this.glyph});

  @override
  Widget build(BuildContext context) {
    return GlowText(
      text: glyph,
      glowColor: MagicalTokens.lavenderGlow,
      style: const TextStyle(
        fontSize: 40,
        color: MagicalTokens.moonWhite,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _MagicalStarPainter extends CustomPainter {
  final List<_Star> stars;
  final Animation<double> animation;

  _MagicalStarPainter({
    required this.stars,
    required this.animation,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value * math.pi * 2;
    final paint = Paint()..color = MagicalTokens.moonWhite.withOpacity(0.25);
    for (final star in stars) {
      final twinkle = 0.5 + 0.5 * math.sin(t + star.phase);
      final opacity = (0.12 + twinkle * 0.25).clamp(0.1, 0.35);
      paint.color = MagicalTokens.moonWhite.withOpacity(opacity);
      final dx = star.offset.dx * size.width;
      final dy = star.offset.dy * size.height * 0.9;
      canvas.drawCircle(Offset(dx, dy), star.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MagicalStarPainter oldDelegate) {
    return oldDelegate.stars != stars;
  }
}

class _WavePainter extends CustomPainter {
  final Animation<double> animation;

  _WavePainter({required this.animation}) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value * math.pi * 2;
    final shift = math.sin(t) * 12;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          MagicalTokens.cyanGlow.withOpacity(0.18),
          MagicalTokens.lavenderGlow.withOpacity(0.18),
        ],
      ).createShader(Offset.zero & size);
    final path = Path()
      ..moveTo(0, size.height * 0.55 + shift)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.4 + shift,
        size.width * 0.5,
        size.height * 0.52 + shift,
      )
      ..quadraticBezierTo(
        size.width * 0.75,
        size.height * 0.65 + shift,
        size.width,
        size.height * 0.52 + shift,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) => false;
}

class _Star {
  final Offset offset;
  final double radius;
  final double phase;

  const _Star({
    required this.offset,
    required this.radius,
    required this.phase,
  });
}
