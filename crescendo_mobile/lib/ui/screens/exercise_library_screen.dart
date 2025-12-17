import 'package:flutter/material.dart';

import '../../data/exercise_seed.dart';
import '../../models/exercise_category.dart';
import '../../models/vocal_exercise.dart';
import '../../services/exercise_recent_repository.dart';
import 'exercise_detail_screen.dart';

class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  final _recentRepo = ExerciseRecentRepository();
  late final List<ExerciseCategory> _categories;
  late final List<VocalExercise> _exercises;
  List<VocalExercise> _recent = [];

  @override
  void initState() {
    super.initState();
    _categories = List<ExerciseCategory>.from(seedExerciseCategories())
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    _exercises = List<VocalExercise>.from(seedVocalExercises());
    _loadRecents();
  }

  Future<void> _loadRecents() async {
    final ids = await _recentRepo.loadRecentIds();
    final map = {for (final e in _exercises) e.id: e};
    final items = <VocalExercise>[];
    for (final id in ids) {
      final ex = map[id];
      if (ex != null) items.add(ex);
    }
    if (mounted) {
      setState(() => _recent = items);
    }
  }

  ExerciseCategory _categoryById(String id) {
    return _categories.firstWhere((c) => c.id == id);
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<VocalExercise>>{};
    for (final ex in _exercises) {
      grouped.putIfAbsent(ex.categoryId, () => []).add(ex);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercise Library'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_recent.isNotEmpty) ...[
            Text('Recent',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._recent.map((ex) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ExerciseTile(
                    exercise: ex,
                    onTap: () => _openDetail(ex),
                  ),
                )),
            const SizedBox(height: 12),
          ],
          for (final category in _categories)
            _CategorySection(
              category: category,
              exercises: grouped[category.id] ?? const [],
              onTap: _openDetail,
            ),
        ],
      ),
    );
  }

  void _openDetail(VocalExercise exercise) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseDetailScreen(
          exercise: exercise,
          category: _categoryById(exercise.categoryId),
        ),
      ),
    ).then((_) => _loadRecents());
  }
}

class _CategorySection extends StatelessWidget {
  final ExerciseCategory category;
  final List<VocalExercise> exercises;
  final void Function(VocalExercise) onTap;

  const _CategorySection({
    required this.category,
    required this.exercises,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(category.title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(category.description),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final ex in exercises)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ExerciseTile(
                exercise: ex,
                onTap: () => onTap(ex),
              ),
            ),
        ],
      ),
    );
  }
}

class ExerciseTile extends StatelessWidget {
  final VocalExercise exercise;
  final VoidCallback onTap;

  const ExerciseTile({
    super.key,
    required this.exercise,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _difficultyColor(exercise.difficulty, context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_typeIcon(exercise.type), color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(exercise.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(_typeLabel(exercise.type),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _difficultyLabel(exercise.difficulty),
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
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

Color _difficultyColor(ExerciseDifficulty difficulty, BuildContext context) {
  return switch (difficulty) {
    ExerciseDifficulty.beginner => Colors.green.shade600,
    ExerciseDifficulty.intermediate => Colors.orange.shade600,
    ExerciseDifficulty.advanced => Colors.red.shade600,
  };
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

IconData _typeIcon(ExerciseType type) {
  return switch (type) {
    ExerciseType.pitchHighway => Icons.multiline_chart,
    ExerciseType.breathTimer => Icons.air,
    ExerciseType.sovtTimer => Icons.spa,
    ExerciseType.sustainedPitchHold => Icons.pause_circle_filled,
    ExerciseType.pitchMatchListening => Icons.hearing,
    ExerciseType.articulationRhythm => Icons.record_voice_over,
    ExerciseType.dynamicsRamp => Icons.volume_up,
    ExerciseType.cooldownRecovery => Icons.self_improvement,
  };
}
