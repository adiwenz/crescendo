import 'package:flutter/material.dart';

import '../../screens/home/styles.dart';
import '../abstract_banner_painter.dart';

class HomeCategoryBannerRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final int bannerStyleId;
  final VoidCallback? onTap;

  const HomeCategoryBannerRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.bannerStyleId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: HomeScreenStyles.categoryBannerDecoration,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(HomeScreenStyles.categoryBannerBorderRadius),
                bottomLeft: Radius.circular(HomeScreenStyles.categoryBannerBorderRadius),
              ),
              child: SizedBox(
                width: 110,
                height: 96,
                child: CustomPaint(
                  painter: AbstractBannerPainter(bannerStyleId, intensity: 1.0),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: HomeScreenStyles.categoryTitle,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: HomeScreenStyles.categorySubtitle,
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
