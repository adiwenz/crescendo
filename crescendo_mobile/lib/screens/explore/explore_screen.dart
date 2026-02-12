import 'package:flutter/material.dart';

import '../../models/exercise_category.dart';
import '../../services/exercise_repository.dart';
import '../../widgets/category_tile.dart';
import '../../widgets/ballad_scaffold.dart';
import '../../theme/ballad_theme.dart';
import 'category_detail_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final ExerciseRepository _exerciseRepo = ExerciseRepository();

  // Define primary categories (Start here)
  static const Set<String> _primaryCategoryIds = {
    'recovery_therapy', // Warmup
    'breathing_support',
    'intonation', // Pitch
    'resonance_placement',
    'onset_release',
  };

  // Define secondary categories (Technique)
  static const Set<String> _secondaryCategoryIds = {
    'sovt',
    'range_building',
    'register_balance',
    'vowel_shaping',
    'agility_runs',
  };

  // Everything else goes in "More/Advanced"

  List<ExerciseCategory> _getPrimaryCategories(List<ExerciseCategory> all) {
    return all.where((c) => _primaryCategoryIds.contains(c.id)).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  List<ExerciseCategory> _getSecondaryCategories(List<ExerciseCategory> all) {
    return all.where((c) => _secondaryCategoryIds.contains(c.id)).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  List<ExerciseCategory> _getAdvancedCategories(List<ExerciseCategory> all) {
    return all
        .where((c) =>
            !_primaryCategoryIds.contains(c.id) &&
            !_secondaryCategoryIds.contains(c.id))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  @override
  Widget build(BuildContext context) {
    final categories = _exerciseRepo.getCategories();
    final allExercises = _exerciseRepo.getExercises();

    // Count exercises per category
    final exerciseCounts = <String, int>{};
    for (final exercise in allExercises) {
      exerciseCounts[exercise.categoryId] = (exerciseCounts[exercise.categoryId] ?? 0) + 1;
    }

    final primaryCategories = _getPrimaryCategories(categories);
    final secondaryCategories = _getSecondaryCategories(categories);
    final advancedCategories = _getAdvancedCategories(categories);

    // Create a map of category to its original index for navigation
    final categoryIndexMap = <String, int>{};
    for (int i = 0; i < categories.length; i++) {
      categoryIndexMap[categories[i].id] = i;
    }

    return BalladScaffold(
      title: 'Explore',
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Explore',
                    style: BalladTheme.titleLarge,
                    textAlign: TextAlign.left,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Find the right exercise',
                    style: BalladTheme.bodyMedium.copyWith(color: BalladTheme.textSecondary),
                    textAlign: TextAlign.left,
                  ),
                ],
              ),
            ),
          ),
            // Category sections
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                children: [
                  // Start here section
                  _CategorySection(
                    title: 'Start here',
                    categories: primaryCategories,
                    exerciseCounts: exerciseCounts,
                    categoryIndexMap: categoryIndexMap,
                    allCategories: categories,
                    isPrimary: true,
                  ),
                  const SizedBox(height: 24),
                  // Technique section
                  _CategorySection(
                    title: 'Technique',
                    categories: secondaryCategories,
                    exerciseCounts: exerciseCounts,
                    categoryIndexMap: categoryIndexMap,
                    allCategories: categories,
                    isPrimary: false,
                  ),
                  const SizedBox(height: 24),
                  // More section (always shown)
                  if (advancedCategories.isNotEmpty)
                    _CategorySection(
                      title: 'More',
                      categories: advancedCategories,
                      exerciseCounts: exerciseCounts,
                      categoryIndexMap: categoryIndexMap,
                      allCategories: categories,
                      isPrimary: false,
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final String title;
  final List<ExerciseCategory> categories;
  final Map<String, int> exerciseCounts;
  final Map<String, int> categoryIndexMap;
  final List<ExerciseCategory> allCategories;
  final bool isPrimary;

  const _CategorySection({
    required this.title,
    required this.categories,
    required this.exerciseCounts,
    required this.categoryIndexMap,
    required this.allCategories,
    required this.isPrimary,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            title,
            style: BalladTheme.titleMedium,
          ),
        ),
        // Category grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.75,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            final exerciseCount = exerciseCounts[category.id] ?? 0;
            final bannerStyleId = category.sortOrder % 8;
            final originalIndex = categoryIndexMap[category.id] ?? 0;

            return CategoryTile(
              title: category.title,
              bannerStyleId: bannerStyleId,
              exerciseCount: exerciseCount,
              isPrimary: isPrimary,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CategoryDetailScreen(
                      category: category,
                      initialCategoryIndex: originalIndex,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
