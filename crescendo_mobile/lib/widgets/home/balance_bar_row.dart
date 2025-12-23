import 'package:flutter/material.dart';
import 'accent_chip.dart';
import 'pill_progress_bar.dart';

class BalanceBarRow extends StatelessWidget {
  final String? label;
  final double value; // 0.0 to 1.0
  final IconData icon;
  final Color accentColor;

  const BalanceBarRow({
    super.key,
    this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Icon chip
        AccentChip(
          icon: icon,
          accentColor: accentColor,
          size: 24,
        ),
        const SizedBox(width: 12),
        // Progress bar
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label != null) ...[
                Text(
                  label!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF7A7A7A),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              PillProgressBar(
                value: value,
                accentColor: accentColor,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

