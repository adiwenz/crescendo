import 'package:flutter/material.dart';

import '../../models/exercise_category.dart';
import '../../models/vocal_exercise.dart';
import '../../services/exercise_recent_repository.dart';
import 'exercise_player_screen.dart';

class ExerciseDetailScreen extends StatelessWidget {
  final VocalExercise exercise;
  final ExerciseCategory category;

  const ExerciseDetailScreen({
    super.key,
    required this.exercise,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    final durationText = exercise.durationSeconds != null
        ? '${exercise.durationSeconds}s'
        : (exercise.reps != null ? '${exercise.reps} reps' : '—');
    return Scaffold(
      appBar: AppBar(title: Text(exercise.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(category.title, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.grey[700])),
          const SizedBox(height: 8),
          Text(exercise.name, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(label: _typeLabel(exercise.type)),
              _InfoChip(label: _difficultyLabel(exercise.difficulty)),
              _InfoChip(label: durationText),
            ],
          ),
          const SizedBox(height: 16),
          _SectionHeader(title: 'How to do it'),
          Text(exercise.description),
          const SizedBox(height: 12),
          _SectionHeader(title: 'Purpose'),
          Text(exercise.purpose),
          const SizedBox(height: 16),
          _SectionHeader(title: 'Tags'),
          Wrap(
            spacing: 8,
            children: exercise.tags.map((t) => Chip(label: Text(t))).toList(),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              await ExerciseRecentRepository().addRecent(exercise.id);
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExercisePlayerScreen(exercise: exercise),
                ),
              );
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold));
  }
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

String _difficultyLabel(ExerciseDifficulty difficulty) {
  return switch (difficulty) {
    ExerciseDifficulty.beginner => 'Beginner',
    ExerciseDifficulty.intermediate => 'Intermediate',
    ExerciseDifficulty.advanced => 'Advanced',
  };
}

String _typeLabel(ExerciseType type) {
  return switch (type) {
    ExerciseType.pitchHighway => 'Pitch Highway',
    ExerciseType.breathTimer => 'Breath Timer',
    ExerciseType.sovtTimer => 'SOVT Timer',
    ExerciseType.sustainedPitchHold => 'Sustained Pitch Hold',
    ExerciseType.pitchMatchListening => 'Pitch Match Listening',
    ExerciseType.articulationRhythm => 'Articulation Rhythm',
    ExerciseType.dynamicsRamp => 'Dynamics Ramp',
    ExerciseType.cooldownRecovery => 'Cooldown Recovery',
  };
}
