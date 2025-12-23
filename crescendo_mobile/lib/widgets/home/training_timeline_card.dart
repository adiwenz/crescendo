import 'package:flutter/material.dart';

enum TrainingStatus {
  completed,
  inProgress,
  next,
}

class TrainingTimelineCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final TrainingStatus status;
  final double? progress;
  final String? trailingText;
  final Color cardTintColor;
  final IconData? singingIcon;
  final VoidCallback? onTap;

  const TrainingTimelineCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.cardTintColor,
    this.progress,
    this.trailingText,
    this.singingIcon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Determine singing icon based on title if not provided
    IconData icon = singingIcon ?? _getSingingIcon(title);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardTintColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: status == TrainingStatus.completed
                ? const Color(0xFF8FC9A8).withOpacity(0.4)
                : status == TrainingStatus.inProgress
                    ? const Color(0xFF7FD1B9).withOpacity(0.4)
                    : const Color(0xFFE6E1DC),
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
            // Singing-themed decorative icon (larger, playful)
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Opacity(
                opacity: 0.15,
                child: Icon(
                  icon,
                  size: 80,
                  color: const Color(0xFF2E2E2E),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2E2E2E),
                            ),
                          ),
                          if (status == TrainingStatus.completed) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8FC9A8),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.check_circle,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: status == TrainingStatus.completed
                              ? const Color(0xFF8FC9A8)
                              : status == TrainingStatus.inProgress
                                  ? const Color(0xFF7FD1B9)
                                  : const Color(0xFF7A7A7A),
                        ),
                      ),
                      if (status == TrainingStatus.inProgress &&
                          progress != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _ProgressBar(value: progress!)),
                            const SizedBox(width: 8),
                            Text(
                              '${(progress! * 100).toInt()}%',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF7FD1B9),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailingText != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFE6E1DC),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          trailingText!,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2E2E2E),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: Color(0xFF7FD1B9),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getSingingIcon(String title) {
    if (title.toLowerCase().contains('warmup')) {
      return Icons.mic_external_on;
    } else if (title.toLowerCase().contains('pitch')) {
      return Icons.trending_up;
    } else if (title.toLowerCase().contains('lip')) {
      return Icons.waves;
    }
    return Icons.music_note;
  }
}

class _ProgressBar extends StatelessWidget {
  final double value;

  const _ProgressBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 8,
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          backgroundColor: const Color(0xFFE6E1DC),
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF7FD1B9)),
        ),
      ),
    );
  }
}
