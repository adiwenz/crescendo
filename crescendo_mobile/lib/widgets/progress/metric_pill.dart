import 'package:flutter/material.dart';
import '../../theme/ballad_theme.dart';

class MetricPill extends StatelessWidget {
  final String label;
  final String value;
  const MetricPill({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: BalladTheme.bodySmall.copyWith(color: BalladTheme.textSecondary)),
          const SizedBox(height: 4),
          Text(value, style: BalladTheme.bodyLarge.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
