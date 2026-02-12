import 'package:flutter/material.dart';
import 'abstract_banner_painter.dart';
import '../ui/theme/app_theme.dart';
import '../theme/ballad_theme.dart';
import 'frosted_panel.dart';

class CategoryTile extends StatelessWidget {
  final String title;
  final int bannerStyleId;
  final int exerciseCount;
  final VoidCallback? onTap;
  final bool isPrimary; // If false, reduces visual intensity

  const CategoryTile({
    super.key,
    required this.title,
    required this.bannerStyleId,
    this.exerciseCount = 0,
    this.onTap,
    this.isPrimary = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    final radius = BorderRadius.circular(AppThemeColors.radiusMd);
    
    return FrostedPanel(
      padding: EdgeInsets.zero,
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
                  children: [
                    Flexible(
                      flex: 1,
                      fit: FlexFit.loose,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: BalladTheme.bodyLarge.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.left,
                          ),
                        ],
                      ),
                    ),
                    // Exercise count
                    if (exerciseCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '$exerciseCount ${exerciseCount == 1 ? 'exercise' : 'exercises'}',
                          style: BalladTheme.bodySmall,
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
