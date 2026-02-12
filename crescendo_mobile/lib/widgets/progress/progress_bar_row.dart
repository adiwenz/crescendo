import 'package:flutter/material.dart';
import '../../theme/ballad_theme.dart';

class ProgressBarRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final double percent; // 0..1

  const ProgressBarRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    final pct = percent.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: BalladTheme.bodyLarge.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Text('${(pct * 100).round()}%', style: BalladTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: BalladTheme.bodySmall.copyWith(color: BalladTheme.textSecondary)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation<Color>(
              BalladTheme.accentPurple,
            ),
          ),
        ),
      ],
    );
  }
}
