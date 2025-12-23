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
    final isActive = status == TrainingStatus.inProgress;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline connector
        SizedBox(
          width: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isFirst) ...[
                Container(
                  width: 2,
                  height: 12,
                  decoration: BoxDecoration(
                    color: status == TrainingStatus.completed
                        ? const Color(0xFF8E8E93)
                        : const Color(0xFFE5E5EA),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
              _StatusIcon(status: status),
              if (!isLast) ...[
                Container(
                  width: 2,
                  height: 60,
                  decoration: BoxDecoration(
                    color: status == TrainingStatus.completed
                        ? const Color(0xFF8E8E93)
                        : const Color(0xFFE5E5EA),
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
        // Content
        Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: EdgeInsets.all(isActive ? 16 : 0),
              decoration: isActive
                  ? BoxDecoration(
                      color: const Color(0xFFFFE5F0), // Soft pink
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    )
                  : null,
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
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight:
                                    isActive ? FontWeight.w600 : FontWeight.w500,
                                color: const Color(0xFF1D1D1F),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              statusText,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF8E8E93),
                              ),
                            ),
                            if (isActive && progress != null) ...[
                              const SizedBox(height: 12),
                              _ProgressBar(value: progress!),
                            ],
                          ],
                        ),
                      ),
                      if (levelText != null) ...[
                        Text(
                          levelText!,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: isActive
                                ? const Color(0xFF1D1D1F)
                                : const Color(0xFF8E8E93),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: isActive
                              ? const Color(0xFF1D1D1F)
                              : const Color(0xFF8E8E93),
                        ),
                      ],
                    ],
                  ),
                  if (isActive) ...[
                    const SizedBox(height: 12),
                    _ResumeButton(onTap: onTap),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
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
          decoration: BoxDecoration(
            color: const Color(0xFF34C759), // Green check
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
          decoration: BoxDecoration(
            color: const Color(0xFFFF3B30), // Red/pink accent
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
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF3B30)),
        ),
      ),
    );
  }
}

class _ResumeButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _ResumeButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.play_arrow,
              size: 18,
              color: Color(0xFF1D1D1F),
            ),
            const SizedBox(width: 6),
            const Text(
              'Resume',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1D1D1F),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

