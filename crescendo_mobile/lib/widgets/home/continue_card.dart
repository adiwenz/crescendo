import 'package:flutter/material.dart';

import '../../screens/home/styles.dart';
import '../abstract_banner_painter.dart';

class ContinueCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final double progress;
  final String? pillText;
  final int bannerStyleId;
  final VoidCallback? onTap;

  const ContinueCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.bannerStyleId,
    this.pillText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 16),
      width: 240,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(HomeScreenStyles.continueCardBorderRadius),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: AbstractBannerPainter(bannerStyleId, intensity: 1.1),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(HomeScreenStyles.continueCardBorderRadius),
                  color: HomeScreenStyles.continueCardOverlay,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: HomeScreenStyles.cardTitle,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: HomeScreenStyles.cardSubtitle,
                    ),
                    const Spacer(),
                    if (pillText != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: HomeScreenStyles.continueCardPillBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.play_circle_fill, size: 16, color: HomeScreenStyles.iconActive),
                            const SizedBox(height: 4, width: 6),
                            Text(
                              pillText!,
                              style: HomeScreenStyles.pillText,
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    _ProgressBar(value: progress),
                  ],
                ),
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
      borderRadius: BorderRadius.circular(10),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: 8,
        backgroundColor: HomeScreenStyles.progressBarBackground,
        valueColor: const AlwaysStoppedAnimation<Color>(HomeScreenStyles.progressBarFill),
      ),
    );
  }
}
