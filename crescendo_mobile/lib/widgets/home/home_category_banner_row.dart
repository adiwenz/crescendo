import 'package:flutter/material.dart';

import '../../screens/home/styles.dart';
import '../abstract_banner_painter.dart';

class HomeCategoryBannerRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final int bannerStyleId;
  final VoidCallback? onTap;
  /// Optional duration in seconds; shown as "0:30" or "2:00".
  final int? durationSec;

  const HomeCategoryBannerRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.bannerStyleId,
    this.onTap,
    this.durationSec,
  });

  static String formatDuration(int sec) {
    if (sec < 60) return '0:${sec.toString().padLeft(2, '0')}';
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Duration for display, rounded to nearest half minute: "30 sec", "1 min", "1.5 min", "2 min", etc.
  static String formatDurationApproximate(int sec) {
    const halfMinSec = 30;
    final halfMins = (sec / halfMinSec).round().clamp(1, 199);
    final roundedSec = halfMins * halfMinSec;
    if (roundedSec < 60) return '$roundedSec sec';
    final wholeMins = roundedSec ~/ 60;
    final remainder = roundedSec % 60;
    if (remainder == 0) return '$wholeMins min';
    return '$wholeMins.5 min';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: HomeScreenStyles.categoryBannerDecoration,
        constraints: const BoxConstraints(minHeight: 96),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(HomeScreenStyles.categoryBannerBorderRadius),
                bottomLeft: Radius.circular(HomeScreenStyles.categoryBannerBorderRadius),
              ),
              child: Container(
                width: 80,
                child: CustomPaint(
                  painter: AbstractBannerPainter(bannerStyleId, intensity: 1.0),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (subtitle.isNotEmpty) ...[
                      Text(
                        subtitle,
                        style: HomeScreenStyles.categoryTitle.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: HomeScreenStyles.categoryTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (durationSec != null && durationSec! > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            formatDurationApproximate(durationSec!),
                            style: HomeScreenStyles.cardSubtitle.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right, color: HomeScreenStyles.iconInactive),
            ),
          ],
        ),
      ),
    );
  }
}
