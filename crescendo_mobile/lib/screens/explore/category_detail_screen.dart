import 'package:flutter/material.dart';

import '../../data/seed_library.dart';
import '../../models/category.dart';
import '../../state/library_store.dart';
import '../../widgets/abstract_banner_painter.dart';
import '../../widgets/exercise_row_banner.dart';

class CategoryDetailScreen extends StatelessWidget {
  final Category category;

  const CategoryDetailScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final exercises = seedExercisesFor(category.id);
    final completed = libraryStore.completedExerciseIds;
    return Scaffold(
      appBar: AppBar(title: Text(category.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 180,
            child: Card(
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: CustomPaint(painter: AbstractBannerPainter(category.bannerStyleId)),
            ),
          ),
          const SizedBox(height: 16),
          Text(category.subtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          ...exercises.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ExerciseRowBanner(
                title: e.title,
                subtitle: e.subtitle,
                bannerStyleId: e.bannerStyleId,
                completed: completed.contains(e.id),
                onTap: () {
                  Navigator.pushNamed(context, '/exercise_detail', arguments: e.id);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
