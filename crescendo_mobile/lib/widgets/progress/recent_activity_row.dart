import 'package:flutter/material.dart';

class RecentActivityRow extends StatelessWidget {
  final String title;
  final String dateLabel;
  final String scoreLabel;

  const RecentActivityRow({
    super.key,
    required this.title,
    required this.dateLabel,
    required this.scoreLabel,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(dateLabel, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(scoreLabel, style: Theme.of(context).textTheme.titleSmall),
      ),
    );
  }
}
