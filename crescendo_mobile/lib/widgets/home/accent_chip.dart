import 'package:flutter/material.dart';

class AccentChip extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final double size;

  const AccentChip({
    super.key,
    required this.icon,
    required this.accentColor,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        size: size * 0.5,
        color: accentColor,
      ),
    );
  }
}

