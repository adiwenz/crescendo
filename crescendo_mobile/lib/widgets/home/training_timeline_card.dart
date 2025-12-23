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
  final String? watermarkImagePath;
  final VoidCallback? onTap;

  const TrainingTimelineCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.status,
    this.progress,
    this.trailingText,
    this.watermarkImagePath,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFE6E1DC),
            width: 1,
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
            // Watermark illustration
            if (watermarkImagePath != null)
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Opacity(
                  opacity: 0.12,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 80,
                      height: 80,
                      child: Image.asset(
                        watermarkImagePath!,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox(),
                      ),
                    ),
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
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2E2E2E),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: status == TrainingStatus.completed
                              ? const Color(0xFF8FC9A8)
                              : status == TrainingStatus.inProgress
                                  ? const Color(0xFF7FD1B9)
                                  : const Color(0xFF7A7A7A),
                        ),
                      ),
                      if (status == TrainingStatus.inProgress &&
                          progress != null) ...[
                        const SizedBox(height: 10),
                        _ProgressBar(value: progress!),
                      ],
                    ],
                  ),
                ),
                if (trailingText != null) ...[
                  Text(
                    trailingText!,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2E2E2E),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: Color(0xFFA5A5A5),
                  ),
                ],
              ],
            ),
          ],
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
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8FC9A8)),
        ),
      ),
    );
  }
}
