import 'package:flutter/material.dart';

import '../../models/exercise.dart';
import '../../state/library_store.dart';
import '../../widgets/abstract_banner_painter.dart';
import 'exercise_session_screen.dart';

class ExerciseDetailScreen extends StatelessWidget {
  final Exercise exercise;

  const ExerciseDetailScreen({super.key, required this.exercise});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(exercise.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 200,
            child: Card(
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: CustomPaint(painter: AbstractBannerPainter(exercise.bannerStyleId)),
            ),
          ),
          const SizedBox(height: 16),
          Text(exercise.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            '${exercise.subtitle}\n\nFocus on clean onsets, relaxed airflow, and centering your pitch.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExerciseSessionScreen(exercise: exercise),
                ),
              );
              await libraryStore.save();
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('Start Exercise'),
          ),
        ],
      ),
    );
  }
}
