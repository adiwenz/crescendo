import 'package:flutter/material.dart';

class TodayExerciseCard extends StatelessWidget {
  final String title;
  final String level;
  final double progress;
  final IconData icon;
  final Color cardColor;
  final VoidCallback? onTap;

  const TodayExerciseCard({
    super.key,
    required this.title,
    required this.level,
    required this.progress,
    required this.icon,
    required this.cardColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 160,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFFE5E5EA),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 28,
                color: const Color(0xFF1D1D1F).withOpacity(0.7),
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1D1D1F),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                level,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF1D1D1F).withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 12),
              _ProgressBar(value: progress),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double value;

  const _ProgressBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          backgroundColor: const Color(0xFFE5E5EA),
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1D1D1F)),
        ),
      ),
    );
  }
}
