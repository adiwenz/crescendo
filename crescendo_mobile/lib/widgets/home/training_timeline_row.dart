import 'package:flutter/material.dart';

enum TrainingStatus {
  completed,
  inProgress,
  next,
}

class TrainingTimelineRow extends StatelessWidget {
  final String title;
  final String statusText;
  final TrainingStatus status;
  final double? progress; // 0.0 to 1.0, only for inProgress
  final String? levelText;
  final VoidCallback? onTap;
  final bool isFirst;
  final bool isLast;

  const TrainingTimelineRow({
    super.key,
    required this.title,
    required this.statusText,
    required this.status,
    this.progress,
    this.levelText,
    this.onTap,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    // Determine card color based on status
    Color? cardColor;
    if (status == TrainingStatus.inProgress) {
      cardColor = const Color(0xFF7FD1B9).withOpacity(0.1); // Mint/teal tint
    } else if (status == TrainingStatus.completed) {
      cardColor = const Color(0xFF8FC9A8).withOpacity(0.1); // Green tint
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Vertical timeline connector - core visual element
          SizedBox(
            width: 28,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isFirst) ...[
                  Container(
                    width: 2,
                    height: 8,
                    decoration: BoxDecoration(
                      color: status == TrainingStatus.completed
                          ? const Color(0xFF8FC9A8) // Completion green
                          : const Color(0xFFD1D1D6), // Light gray
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
                _StatusIcon(status: status),
                if (!isLast) ...[
                  Container(
                    width: 2,
                    height: 80,
                    decoration: BoxDecoration(
                      color: status == TrainingStatus.completed
                          ? const Color(0xFF8FC9A8) // Completion green
                          : const Color(0xFFD1D1D6), // Light gray
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Content card
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor ?? Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFFE5E5EA),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                                  color: Color(0xFF1D1D1F),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                  color: status == TrainingStatus.completed
                                      ? const Color(0xFF8FC9A8)
                                      : status == TrainingStatus.inProgress
                                          ? const Color(0xFF7FD1B9)
                                          : const Color(0xFF8E8E93),
                                ),
                              ),
                              if (status == TrainingStatus.inProgress &&
                                  progress != null) ...[
                                const SizedBox(height: 12),
                                _ProgressBar(value: progress!),
                              ],
                            ],
                          ),
                        ),
                        if (levelText != null) ...[
                          Text(
                            levelText!,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF8E8E93),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: Color(0xFF8E8E93),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final TrainingStatus status;

  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    const size = 24.0;

    switch (status) {
      case TrainingStatus.completed:
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Color(0xFF8FC9A8), // Completion green
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check,
            size: 16,
            color: Colors.white,
          ),
        );
      case TrainingStatus.inProgress:
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Color(0xFF7FD1B9), // Mint/teal accent
            shape: BoxShape.circle,
          ),
        );
      case TrainingStatus.next:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFFD1D1D6),
              width: 2,
            ),
          ),
        );
    }
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
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF7FD1B9)),
        ),
      ),
    );
  }
}
