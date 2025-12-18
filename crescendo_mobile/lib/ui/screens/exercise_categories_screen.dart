import 'package:flutter/material.dart';

import '../../models/exercise_category.dart';
import '../../services/exercise_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/primary_icon_tile.dart';
import '../widgets/exercise_icon.dart';
import 'exercise_list_screen.dart';

class ExerciseCategoriesScreen extends StatelessWidget {
  const ExerciseCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    final repo = ExerciseRepository();
    final categories = repo.getCategories();
    final pastelTiles = [
      colors.surface1,
      colors.mintAccent.withOpacity(0.6),
      colors.goldAccent.withOpacity(0.5),
      colors.blueAccent.withOpacity(0.35),
      colors.surface2,
      colors.mintAccent.withOpacity(0.45),
    ];
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Exercise Library'),
      ),
      body: AppBackground(
        child: SafeArea(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1,
            ),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              return PrimaryIconTile(
                icon: ExerciseIcon(iconKey: category.iconKey),
                label: category.title,
                backgroundColor:
                    colors.isDark ? null : pastelTiles[index % pastelTiles.length],
                onTap: () => _openCategory(context, category),
              );
            },
          ),
        ),
      ),
    );
  }

  void _openCategory(BuildContext context, ExerciseCategory category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseListScreen(categoryId: category.id),
      ),
    );
  }
}
