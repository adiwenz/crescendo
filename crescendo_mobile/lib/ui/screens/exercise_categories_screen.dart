import 'package:flutter/material.dart';

import '../../models/exercise_category.dart';
import '../../services/exercise_repository.dart';
import '../widgets/exercise_tile.dart';
import 'exercise_list_screen.dart';

class ExerciseCategoriesScreen extends StatelessWidget {
  const ExerciseCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = ExerciseRepository();
    final categories = repo.getCategories();
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Exercise Library'),
      ),
      body: GridView.builder(
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
          return ExerciseTile(
            title: category.title,
            subtitle: null,
            iconKey: category.iconKey,
            onTap: () => _openCategory(context, category),
          );
        },
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
