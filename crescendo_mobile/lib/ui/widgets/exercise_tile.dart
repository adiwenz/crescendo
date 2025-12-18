import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'exercise_icon.dart';
import 'frosted_card.dart';

class ExerciseTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String iconKey;
  final String? chipLabel;
  final Widget? preview;
  final Widget? badge;
  final Widget? footer;
  final VoidCallback onTap;

  const ExerciseTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.iconKey,
    this.chipLabel,
    this.preview,
    this.badge,
    this.footer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showCenteredIcon = preview == null;
    if (showCenteredIcon) {
      return AspectRatio(
        aspectRatio: 1,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: FrostedCard(
              borderRadius: BorderRadius.circular(22),
              padding: const EdgeInsets.all(12),
              child: Stack(
                children: [
                  Align(
                    alignment: const Alignment(0, -0.2),
                    child: ExerciseIcon(iconKey: iconKey, size: 60),
                  ),
                  if (badge != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: badge!,
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: 1,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: FrostedCard(
            borderRadius: BorderRadius.circular(22),
            padding: EdgeInsets.zero,
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (preview != null)
                      ClipRRect(
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(22)),
                        child: SizedBox(
                          height: 72,
                          width: double.infinity,
                          child: preview,
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ExerciseIcon(iconKey: iconKey, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            if (subtitle != null) ...[
                              Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                            if (chipLabel != null) ...[
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.glassFill,
                                      border: Border.all(
                                        color: AppColors.glassBorder,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      chipLabel!,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            if (footer != null)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: ClipRect(
                                    child: SingleChildScrollView(
                                      physics:
                                          const ClampingScrollPhysics(),
                                      child: footer!,
                                    ),
                                  ),
                                ),
                              ),
                            if (footer == null) const Spacer(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (badge != null)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: badge!,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
