import 'package:flutter/material.dart';

class ProgressPill extends StatelessWidget {
  final double progress;
  final String label;

  const ProgressPill({
    super.key,
    required this.progress,
    this.label = 'Complete',
  });

  @override
  Widget build(BuildContext context) {
    final percentage = (progress * 100).round();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3B7A6).withOpacity(0.15),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$percentage% $label',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF2E2E2E),
              ),
            ),
          ),
          Row(
            children: List.generate(5, (index) {
              final isFilled = index < (progress * 5).round();
              return Container(
                margin: const EdgeInsets.only(left: 4),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isFilled
                      ? const Color(0xFFF3B7A6)
                      : const Color(0xFFE6E1DC),
                  shape: BoxShape.circle,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

