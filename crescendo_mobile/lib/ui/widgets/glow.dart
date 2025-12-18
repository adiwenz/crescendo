import 'package:flutter/material.dart';

class GlowText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Color glowColor;

  const GlowText({
    super.key,
    required this.text,
    required this.style,
    required this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: style.copyWith(
        shadows: [
          Shadow(color: glowColor.withOpacity(0.4), blurRadius: 12),
          Shadow(color: glowColor.withOpacity(0.2), blurRadius: 24),
        ],
      ),
    );
  }
}

class GlowIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;
  final Color glowColor;

  const GlowIcon({
    super.key,
    required this.icon,
    required this.size,
    required this.color,
    required this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: size,
      color: color,
      shadows: [
        Shadow(color: glowColor.withOpacity(0.4), blurRadius: 12),
        Shadow(color: glowColor.withOpacity(0.2), blurRadius: 24),
      ],
    );
  }
}
