import 'dart:math' as math;

import 'package:flutter/material.dart';

class Breathing extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double minScale;
  final double maxScale;
  final double minOpacity;
  final double maxOpacity;

  const Breathing({
    super.key,
    required this.child,
    this.duration = const Duration(seconds: 6),
    this.minScale = 0.98,
    this.maxScale = 1.02,
    this.minOpacity = 0.85,
    this.maxOpacity = 1.0,
  });

  @override
  State<Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<Breathing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
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
        final t = _controller.value;
        final wave = 0.5 + 0.5 * math.sin(t * math.pi * 2);
        final scale =
            widget.minScale + (widget.maxScale - widget.minScale) * wave;
        final opacity =
            widget.minOpacity + (widget.maxOpacity - widget.minOpacity) * wave;
        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: widget.child,
    );
  }
}
