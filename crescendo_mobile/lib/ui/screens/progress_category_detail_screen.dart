import 'package:flutter/material.dart';

import '../../data/seed_library.dart';
import '../../models/category.dart';
import '../../models/exercise.dart';
import '../../routing/exercise_route_registry.dart';
import '../../state/library_store.dart';

class CategoryProgressDetailScreen extends StatelessWidget {
  final String categoryId;

  const CategoryProgressDetailScreen({super.key, required this.categoryId});

  @override
  Widget build(BuildContext context) {
    final categories = seedLibraryCategories();
    final Category category =
        categories.firstWhere((c) => c.id == categoryId, orElse: () => categories.first);
    final List<Exercise> exercises = seedExercisesFor(category.id);
    final best = libraryStore.bestScores;
    final last = libraryStore.lastScores;
    final lastCompleted = libraryStore.lastCompletedAt;
    final times = libraryStore.timesCompleted;

    return Scaffold(
      appBar: AppBar(title: Text(category.title)),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, index) {
          final ex = exercises[index];
          final completed = (times[ex.id] ?? 0) > 0 || libraryStore.completedExerciseIds.contains(ex.id);
          final bestScore = best[ex.id];
          final lastScore = last[ex.id];
          final lastDate = lastCompleted[ex.id];
          return ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            tileColor: Colors.white,
            leading: CircleAvatar(
              backgroundColor: Colors.grey.shade200,
              child: completed ? const Icon(Icons.check, color: Colors.green) : const Icon(Icons.music_note),
            ),
            title: Text(ex.title),
            subtitle: Text(
              [
                if (bestScore != null) 'Best: $bestScore',
                if (lastScore != null) 'Last: $lastScore',
                if (lastDate != null) _dateLabel(lastDate),
              ].join(' • '),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              final opened = ExerciseRouteRegistry.open(context, ex.id);
              if (!opened) {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Not wired yet'),
                    content: Text('Exercise ${ex.title} is not wired to a screen.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                    ],
                  ),
                );
              }
            },
          );
        },
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemCount: exercises.length,
      ),
    );
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    return '${_month(date.month)} ${date.day}';
  }

  String _month(int m) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (m < 1 || m > 12) return '';
    return names[m - 1];
  }
}
