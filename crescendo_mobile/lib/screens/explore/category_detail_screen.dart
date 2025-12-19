import 'package:flutter/material.dart';

import '../../data/seed_library.dart';
import '../../models/category.dart';
import '../../services/attempt_repository.dart';
import '../../state/library_store.dart';
import '../../widgets/abstract_banner_painter.dart';
import '../../widgets/exercise_row_banner.dart';
import 'exercise_preview_screen.dart';

class CategoryDetailScreen extends StatefulWidget {
  final Category category;

  const CategoryDetailScreen({super.key, required this.category});

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  final AttemptRepository _attempts = AttemptRepository.instance;

  @override
  void initState() {
    super.initState();
    _attempts.addListener(_onAttemptsChanged);
  }

  @override
  void dispose() {
    _attempts.removeListener(_onAttemptsChanged);
    super.dispose();
  }

  void _onAttemptsChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final exercises = seedExercisesFor(widget.category.id);
    final completedIds = _attempts.cache.map((a) => a.exerciseId).toSet()
      ..addAll(libraryStore.completedExerciseIds);
    return Scaffold(
      appBar: AppBar(title: Text(widget.category.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 180,
            child: Card(
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: CustomPaint(painter: AbstractBannerPainter(widget.category.bannerStyleId)),
            ),
          ),
          const SizedBox(height: 16),
          Text(widget.category.subtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          ...exercises.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ExerciseRowBanner(
                title: e.title,
                subtitle: e.subtitle,
                bannerStyleId: e.bannerStyleId,
                completed: completedIds.contains(e.id),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExercisePreviewScreen(exerciseId: e.id),
                    ),
                  );
                  await _attempts.refresh();
                  await libraryStore.load();
                  if (mounted) setState(() {});
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
