import 'package:flutter/material.dart';
import 'abstract_banner_painter.dart';

class ExerciseRowBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final int bannerStyleId;
  final bool completed;
  final VoidCallback? onTap;

  const ExerciseRowBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.bannerStyleId,
    this.completed = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 3,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 110,
          child: Row(
            children: [
              SizedBox(
                width: 110,
                height: 110,
                child: CustomPaint(
                  painter: AbstractBannerPainter(bannerStyleId),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  completed ? Icons.check_circle : Icons.chevron_right,
                  color: completed ? Theme.of(context).colorScheme.primary : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
