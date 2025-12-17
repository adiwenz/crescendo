import 'package:flutter/material.dart';

import '../../data/progress_repository.dart';
import '../../models/vocal_exercise.dart';
import '../../services/exercise_repository.dart';
import '../widgets/exercise_icon.dart';
import 'exercise_navigation.dart';

class ExerciseInfoScreen extends StatefulWidget {
  final String exerciseId;

  const ExerciseInfoScreen({super.key, required this.exerciseId});

  @override
  State<ExerciseInfoScreen> createState() => _ExerciseInfoScreenState();
}

class _ExerciseInfoScreenState extends State<ExerciseInfoScreen> {
  final _repo = ExerciseRepository();
  final _progress = ProgressRepository();
  double? _lastScore;

  @override
  void initState() {
    super.initState();
    _loadLastScore();
  }

  Future<void> _loadLastScore() async {
    final attempts = await _progress.fetchAttemptsForExercise(widget.exerciseId);
    if (!mounted) return;
    if (attempts.isEmpty) {
      setState(() => _lastScore = null);
      return;
    }
    attempts.sort((a, b) => b.completedAt.compareTo(a.completedAt));
    setState(() => _lastScore = attempts.first.overallScore);
  }

  @override
  Widget build(BuildContext context) {
    final exercise = _repo.getExercise(widget.exerciseId);
    final durationSeconds = exercise.durationSeconds;
    final timeChip = durationSeconds != null
        ? (durationSeconds < 60
            ? '${durationSeconds}s'
            : '${exercise.estimatedMinutes} min')
        : (exercise.reps != null ? '${exercise.reps} reps' : '—');
    final typeLabel = _typeLabel(exercise.type);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(exercise.name),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              ExerciseIcon(iconKey: exercise.iconKey, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Text(exercise.name,
                    style: Theme.of(context).textTheme.headlineSmall),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(label: typeLabel),
              _InfoChip(label: _difficultyLabel(exercise.difficulty)),
              _InfoChip(label: timeChip),
            ],
          ),
          const SizedBox(height: 16),
          _SectionHeader(title: 'How to do it'),
          Text(exercise.description),
          const SizedBox(height: 12),
          _SectionHeader(title: 'Purpose'),
          Text(exercise.purpose),
          const SizedBox(height: 12),
          _SectionHeader(title: 'Targets'),
          ..._targetsForExercise(exercise)
              .map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('- $t'),
                  ))
              .toList(),
          const SizedBox(height: 12),
          _SectionHeader(title: 'Tags'),
          Wrap(
            spacing: 8,
            children: exercise.tags.map((t) => Chip(label: Text(t))).toList(),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => buildExerciseScreen(exercise)),
              );
              if (result is double) {
                setState(() => _lastScore = result);
              } else {
                await _loadLastScore();
              }
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Exercise'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back'),
          ),
          const SizedBox(height: 16),
          Text(
            'Last score: ${_lastScore?.toStringAsFixed(0) ?? '—'}%',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  List<String> _targetsForExercise(VocalExercise exercise) {
    if (exercise.type == ExerciseType.pitchHighway &&
        exercise.highwaySpec?.segments.isNotEmpty == true) {
      final tol = exercise.highwaySpec!.segments.first.toleranceCents.round();
      return ['Pitch accuracy ±$tol cents', 'Stay centered on each note'];
    }
    if (exercise.type == ExerciseType.sustainedPitchHold) {
      return ['Hold within ±25 cents', 'Maintain stability for 3 seconds'];
    }
    if (exercise.type == ExerciseType.dynamicsRamp) {
      return ['Match the loudness ramp', 'Keep tone stable'];
    }
    if (exercise.type == ExerciseType.pitchMatchListening) {
      return ['Match the reference pitch', 'Listen then sing'];
    }
    if (exercise.type == ExerciseType.breathTimer ||
        exercise.type == ExerciseType.sovtTimer ||
        exercise.type == ExerciseType.cooldownRecovery) {
      return ['Complete the full timer cycle', 'Maintain steady airflow'];
    }
    return ['Follow the on-screen guidance'];
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
      ExerciseType.sustainedPitchHold => 'Sustained Hold',
      ExerciseType.pitchMatchListening => 'Pitch Match',
      ExerciseType.articulationRhythm => 'Articulation Rhythm',
      ExerciseType.dynamicsRamp => 'Dynamics Ramp',
      ExerciseType.cooldownRecovery => 'Recovery',
    };
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold));
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
