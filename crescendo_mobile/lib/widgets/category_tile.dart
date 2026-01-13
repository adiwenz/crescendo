import 'package:flutter/material.dart';
import 'abstract_banner_painter.dart';
import '../ui/theme/app_theme.dart';

class CategoryTile extends StatelessWidget {
  final String title;
  final String description;
  final int bannerStyleId;
  final int exerciseCount;
  final VoidCallback? onTap;
  final bool isPrimary; // If false, reduces visual intensity

  const CategoryTile({
    super.key,
    required this.title,
    required this.description,
    required this.bannerStyleId,
    this.exerciseCount = 0,
    this.onTap,
    this.isPrimary = true,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Colored artwork block
            SizedBox(
              height: 100,
              child: CustomPaint(
                painter: AbstractBannerPainter(
                  bannerStyleId,
                  intensity: isPrimary ? 1.0 : 0.5, // Reduce intensity for secondary
                ),
              ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              description,
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Exercise count
                    if (exerciseCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '$exerciseCount ${exerciseCount == 1 ? 'exercise' : 'exercises'}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
