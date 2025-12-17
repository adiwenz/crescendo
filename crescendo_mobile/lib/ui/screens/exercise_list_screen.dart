import 'package:flutter/material.dart';

import '../../models/vocal_exercise.dart';
import '../../services/exercise_repository.dart';
import '../../services/unlock_service.dart';
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
    final unlockFuture = _loadUnlocks(exercises);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(category.title),
      ),
      body: FutureBuilder<Map<String, int>>(
        future: unlockFuture,
        builder: (context, snapshot) {
          final unlocks = snapshot.data ?? const {};
          return Column(
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
                    final badge = exercise.type == ExerciseType.pitchHighway
                        ? _buildUnlockBadge(context, unlocks[exercise.id] ?? 0)
                        : null;
                    return ExerciseTile(
                      title: exercise.name,
                      subtitle: _typeLabel(exercise.type),
                      iconKey: exercise.iconKey,
                      chipLabel: _typeLabel(exercise.type),
                      preview: ExercisePreviewMini(exercise: exercise),
                      badge: badge,
                      onTap: () => _openExercise(context, exercise),
                    );
                  },
                ),
              ),
            ],
          );
        },
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

  Future<Map<String, int>> _loadUnlocks(List<VocalExercise> exercises) async {
    final service = UnlockService();
    final Map<String, int> unlocks = {};
    for (final ex in exercises) {
      if (ex.type != ExerciseType.pitchHighway) continue;
      unlocks[ex.id] = await service.getMaxUnlocked(ex.id);
    }
    return unlocks;
  }

  Widget _buildUnlockBadge(BuildContext context, int maxUnlocked) {
    final level = (maxUnlocked + 1).clamp(1, 3);
    final locked = maxUnlocked < 2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Lvl $level',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (locked) ...[
            const SizedBox(width: 4),
            const Icon(Icons.lock, size: 12),
          ],
        ],
      ),
    );
  }
}
