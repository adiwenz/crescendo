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
    // Determine singing icon if not provided
    IconData icon = watermarkIcon ?? _getSingingIcon(title);

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
            border: Border.all(
              color: const Color(0xFFE6E1DC),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Large singing-themed decorative icon
              Positioned(
                top: 0,
                right: 0,
                child: Opacity(
                  opacity: 0.2,
                  child: Icon(
                    icon,
                    size: 90,
                    color: const Color(0xFF2E2E2E),
                  ),
                ),
              ),
              // Small decorative music notes
              Positioned(
                top: 8,
                left: 8,
                child: Opacity(
                  opacity: 0.3,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.music_note,
                        size: 16,
                        color: const Color(0xFF2E2E2E),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.music_note,
                        size: 14,
                        color: const Color(0xFF2E2E2E),
                      ),
                    ],
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2E2E2E),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      level,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2E2E2E),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _ProgressBar(value: progress)),
                      const SizedBox(width: 8),
                      Text(
                        '${(progress * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2E2E2E),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getSingingIcon(String title) {
    if (title.toLowerCase().contains('warmup')) {
      return Icons.local_fire_department;
    } else if (title.toLowerCase().contains('pitch')) {
      return Icons.graphic_eq;
    }
    return Icons.mic;
  }
}

class _ProgressBar extends StatelessWidget {
  final double value;

  const _ProgressBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6,
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          backgroundColor: Colors.white.withOpacity(0.5),
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2E2E2E)),
        ),
      ),
    );
  }
}
