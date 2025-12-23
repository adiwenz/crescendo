import 'package:flutter/material.dart';
import 'checklist_row.dart';
import 'completion_check.dart';
import 'soft_pill_card.dart';

class TodayExercisesTimeline extends StatelessWidget {
  final List<ExerciseItem> items;

  const TodayExercisesTimeline({
    super.key,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    const cardSpacing = 10.0;
    const circleSize = 24.0;
    const lineTopOffset = 12.0;
    const lineBottomOffset = 12.0;

    return Stack(
      children: [
        // Vertical connecting line (continuous, behind circles)
        Positioned(
          left: 12,
          top: lineTopOffset + circleSize / 2,
          bottom: lineBottomOffset + circleSize / 2,
          child: Container(
            width: 2,
            decoration: BoxDecoration(
              color: const Color(0xFFE6E1DC),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
        // Cards with checkmarks
        Column(
          children: [
            for (int i = 0; i < items.length; i++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Checkmark circle area (aligned with line)
                  SizedBox(
                    width: 28,
                    child: CompletionCheck(
                      isCompleted: items[i].isCompleted,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Card
                  Expanded(
                    child: SoftPillCard(
                      onTap: items[i].onTap,
                      child: ChecklistRow(
                        title: items[i].title,
                        subtitle: items[i].subtitle,
                        icon: items[i].icon,
                        accentColor: items[i].accentColor,
                        isCompleted: items[i].isCompleted,
                        trailing: items[i].trailing,
                      ),
                    ),
                  ),
                ],
              ),
              if (i < items.length - 1) const SizedBox(height: cardSpacing),
            ],
          ],
        ),
      ],
    );
  }
}

class ExerciseItem {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color accentColor;
  final bool isCompleted;
  final VoidCallback? onTap;
  final Widget? trailing;

  ExerciseItem({
    required this.title,
    required this.icon,
    required this.accentColor,
    this.subtitle,
    this.isCompleted = false,
    this.onTap,
    this.trailing,
  });
}

