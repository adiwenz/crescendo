import 'package:flutter/material.dart';
import 'abstract_banner_painter.dart';
import '../ui/theme/app_theme.dart';

class BannerCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final int bannerStyleId;
  final VoidCallback? onTap;
  final Widget? trailing;

  const BannerCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.bannerStyleId,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    final radius = BorderRadius.circular(AppThemeColors.radiusMd);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceGlass,
        borderRadius: radius,
        border: Border.all(color: colors.borderGlass, width: 1),
        boxShadow: colors.elevationShadow,
      ),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 140,
          child: Row(
            children: [
              SizedBox(
                width: 140,
                height: 140,
                child: CustomPaint(
                  painter: AbstractBannerPainter(bannerStyleId),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(subtitle, style: Theme.of(context).textTheme.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ),
              if (trailing != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: trailing,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
