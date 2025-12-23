import 'package:flutter/material.dart';

class PillProgressBar extends StatelessWidget {
  final double value; // 0.0 to 1.0
  final Color accentColor;

  const PillProgressBar({
    super.key,
    required this.value,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fillWidth = constraints.maxWidth * value.clamp(0.0, 1.0);

        return ClipRRect(
          borderRadius: BorderRadius.circular(999), // Full pill
          child: SizedBox(
            height: 11,
            child: Stack(
              children: [
                // Track/background
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6E1DC).withOpacity(0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                // Fill
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  width: fillWidth,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.80),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

