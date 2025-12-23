import 'package:flutter/material.dart';

class ExerciseMiniCard extends StatelessWidget {
  final String title;
  final String level;
  final double progress;
  final String? backgroundImagePath;
  final VoidCallback? onTap;

  const ExerciseMiniCard({
    super.key,
    required this.title,
    required this.level,
    required this.progress,
    this.backgroundImagePath,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Container(
            height: 160,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.89),
              borderRadius: BorderRadius.circular(24),
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
              children: [
                // Watermark illustration (bottom-right, very low opacity)
                if (backgroundImagePath != null)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Opacity(
                      opacity: 0.08,
                      child: SizedBox(
                        width: 90,
                        height: 90,
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
                // Content
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
