import 'package:flutter/material.dart';

class ExerciseMiniCard extends StatelessWidget {
  final String title;
  final String level;
  final double progress;
  final Color cardTintColor;
  final IconData? watermarkIcon;
  final VoidCallback? onTap;

  const ExerciseMiniCard({
    super.key,
    required this.title,
    required this.level,
    required this.progress,
    required this.cardTintColor,
    this.watermarkIcon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 160,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardTintColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Watermark icon (faint)
              if (watermarkIcon != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Opacity(
                    opacity: 0.1,
                    child: Icon(
                      watermarkIcon,
                      size: 72,
                      color: const Color(0xFF2E2E2E),
                    ),
                  ),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2E2E2E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    level,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF7A7A7A),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ProgressBar(value: progress),
                ],
              ),
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
          backgroundColor: const Color(0xFFE6E1DC),
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2E2E2E)),
        ),
      ),
    );
  }
}

