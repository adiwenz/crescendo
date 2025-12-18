import 'package:flutter/material.dart';

import '../../models/vocal_exercise.dart';
import '../../models/exercise_instance.dart';
import '../../services/exercise_repository.dart';
import '../../services/unlock_service.dart';
import '../../services/range_exercise_generator.dart';
import '../../services/range_store.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/exercise_preview_mini.dart';
import '../widgets/exercise_tile.dart';
import 'exercise_info_screen.dart';
import 'exercise_player_screen.dart';
import '../../models/pitch_highway_difficulty.dart';

class ExerciseListScreen extends StatefulWidget {
  final String categoryId;

  const ExerciseListScreen({super.key, required this.categoryId});

  @override
  State<ExerciseListScreen> createState() => _ExerciseListScreenState();
}

class _ExerciseListScreenState extends State<ExerciseListScreen> {
  @override
  Widget build(BuildContext context) {
    final repo = ExerciseRepository();
    final category = repo.getCategory(widget.categoryId);
    final exercises = repo.getExercisesForCategory(widget.categoryId);
    final unlockFuture = _loadUnlocks(exercises);
    final rangeFuture = RangeStore().getRange();
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(category.title),
      ),
      body: AppBackground(
        child: SafeArea(
          child: FutureBuilder<(Map<String, int>, (int?, int?))>(
            future: Future.wait([unlockFuture, rangeFuture]).then(
              (values) => (values[0] as Map<String, int>, values[1] as (int?, int?)),
            ),
            builder: (context, snapshot) {
              final unlocks = snapshot.data?.$1 ?? const {};
              final range = snapshot.data?.$2 ?? (null, null);
              final lowest = range.$1;
              final highest = range.$2;
              final generator = RangeExerciseGenerator();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (category.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        category.description,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
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
                        final instances =
                            (exercise.type == ExerciseType.pitchHighway &&
                                    lowest != null &&
                                    highest != null)
                                ? generator.generate(
                                    exercise: exercise,
                                    lowestMidi: lowest,
                                    highestMidi: highest)
                                : const <ExerciseInstance>[];
                        return ExerciseTile(
                          title: exercise.name,
                          subtitle: _typeLabel(exercise.type),
                          iconKey: exercise.iconKey,
                          chipLabel: _typeLabel(exercise.type),
                          preview: ExercisePreviewMini(exercise: exercise),
                          badge: badge,
                          onTap: () => _openExercise(context, exercise),
                          footer: instances.isNotEmpty
                              ? _StepList(
                                  exercise: exercise,
                                  instances: instances,
                                  onStart: (inst) =>
                                      _startInstance(context, exercise, inst),
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
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
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Lvl $level',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
          ),
          if (locked) ...[
            const SizedBox(width: 4),
            const Icon(Icons.lock, size: 12, color: AppColors.textPrimary),
          ],
        ],
      ),
    );
  }

  void _startInstance(
    BuildContext context,
    VocalExercise base,
    ExerciseInstance instance,
  ) {
    final ex = instance.apply(base);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExercisePlayerScreen(
          exercise: ex,
          pitchDifficulty: PitchHighwayDifficulty.medium,
        ),
      ),
    );
  }
}

class _StepList extends StatelessWidget {
  final VocalExercise exercise;
  final List<ExerciseInstance> instances;
  final ValueChanged<ExerciseInstance> onStart;

  const _StepList({
    required this.exercise,
    required this.instances,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          'Step series',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
        ),
        ...instances.map(
          (i) => InkWell(
            onTap: () => onStart(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.play_arrow, size: 16, color: AppColors.textPrimary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      i.label,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
