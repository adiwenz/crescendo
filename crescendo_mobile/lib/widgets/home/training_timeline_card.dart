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
  final String? backgroundImagePath;
  final VoidCallback? onTap;

  const TrainingTimelineCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.status,
    this.progress,
    this.trailingText,
    this.backgroundImagePath,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.89),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 24,
                spreadRadius: 0,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Watermark illustration (bottom-right, very low opacity)
              if (backgroundImagePath != null)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Opacity(
                    opacity: 0.08,
                    child: SizedBox(
                      width: 100,
                      height: 100,
                      child: Image.asset(
                        backgroundImagePath!,
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomRight,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox(),
                      ),
                    ),
                  ),
                ),
              // Optional readability scrim (left-to-right gradient)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.white.withOpacity(0.92),
                        Colors.white.withOpacity(0.55),
                        Colors.white.withOpacity(0.10),
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
              // Text content
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
                    const SizedBox(width: 8),
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
