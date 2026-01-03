import 'package:flutter/material.dart';
import '../../ui/theme/app_theme.dart';

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
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text('${(pct * 100).round()}%', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: AppThemeColors.light.divider,
            valueColor: AlwaysStoppedAnimation<Color>(
              AppThemeColors.light.accentPurple,
            ),
          ),
        ),
      ],
    );
  }
}
