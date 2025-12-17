import 'package:flutter/material.dart';

import '../../models/vocal_exercise.dart';
import '../../services/exercise_repository.dart';
import '../widgets/exercise_preview_mini.dart';
import '../widgets/exercise_tile.dart';
import 'exercise_info_screen.dart';

class ExerciseListScreen extends StatelessWidget {
  final String categoryId;

  const ExerciseListScreen({super.key, required this.categoryId});

  @override
  Widget build(BuildContext context) {
    final repo = ExerciseRepository();
    final category = repo.getCategory(categoryId);
    final exercises = repo.getExercisesForCategory(categoryId);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(category.title),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (category.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                category.description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[700],
                    ),
              ),
            ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1,
              ),
              itemCount: exercises.length,
              itemBuilder: (context, index) {
                final exercise = exercises[index];
                return ExerciseTile(
                  title: exercise.name,
                  subtitle: _typeLabel(exercise.type),
                  iconKey: exercise.iconKey,
                  chipLabel: _typeLabel(exercise.type),
                  preview: ExercisePreviewMini(exercise: exercise),
                  onTap: () => _openExercise(context, exercise),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openExercise(BuildContext context, VocalExercise exercise) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseInfoScreen(exerciseId: exercise.id),
      ),
    );
  }

  String _typeLabel(ExerciseType type) {
    return switch (type) {
      ExerciseType.pitchHighway => 'Pitch Highway',
      ExerciseType.breathTimer => 'Breath Timer',
      ExerciseType.sovtTimer => 'SOVT Timer',
      ExerciseType.sustainedPitchHold => 'Sustained Hold',
      ExerciseType.pitchMatchListening => 'Pitch Match',
      ExerciseType.articulationRhythm => 'Articulation Rhythm',
      ExerciseType.dynamicsRamp => 'Dynamics Ramp',
      ExerciseType.cooldownRecovery => 'Recovery',
    };
  }
}
