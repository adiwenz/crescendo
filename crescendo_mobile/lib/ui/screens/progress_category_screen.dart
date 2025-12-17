import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/exercise_attempt.dart';
import '../../models/exercise_category.dart';
import '../../models/progress_stats.dart';
import '../../models/vocal_exercise.dart';
import '../../services/progress_service.dart';
import '../../services/progress_stats.dart';
import '../progress/progress_range.dart';
import '../widgets/exercise_icon.dart';
import 'progress_exercise_screen.dart';

class ProgressCategoryScreen extends StatefulWidget {
  final ExerciseCategory category;
  final List<VocalExercise> exercises;

  const ProgressCategoryScreen({
    super.key,
    required this.category,
    required this.exercises,
  });

  @override
  State<ProgressCategoryScreen> createState() => _ProgressCategoryScreenState();
}

class _ProgressCategoryScreenState extends State<ProgressCategoryScreen> {
  final ProgressService _progress = ProgressService();
  ProgressRange _range = ProgressRange.days14;

  @override
  void initState() {
    super.initState();
    unawaited(_progress.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final exercises =
        widget.exercises.where((e) => e.categoryId == widget.category.id).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category.title),
      ),
      body: StreamBuilder<ProgressSnapshot<ExerciseAttempt>>(
        stream: _progress.stream,
        initialData: _progress.snapshot(),
        builder: (context, snapshot) {
          final attempts = snapshot.data?.attempts ?? [];
          final filtered = filterAttemptsByWindow(
            attempts,
            now: DateTime.now(),
            window: _range.window,
          );
          final stats = exercises
              .map((ex) => MapEntry(
                    ex,
                    computeExerciseStats(exerciseId: ex.id, attempts: filtered),
                  ))
              .toList()
            ..sort((a, b) {
              final aScore = a.value.averageRecent ?? 0;
              final bScore = b.value.averageRecent ?? 0;
              return aScore.compareTo(bScore);
            });

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _RangeToggle(
                value: _range,
                onChanged: (next) => setState(() => _range = next),
              ),
              const SizedBox(height: 12),
              ...stats.map((entry) {
                final exercise = entry.key;
                final stat = entry.value;
                return _ExerciseRow(
                  exercise: exercise,
                  stats: stat,
                  onTap: () => _openExercise(exercise),
                );
              }).toList(),
            ],
          );
        },
      ),
    );
  }

  void _openExercise(VocalExercise exercise) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProgressExerciseScreen(exercise: exercise),
      ),
    );
  }
}

class _RangeToggle extends StatelessWidget {
  final ProgressRange value;
  final ValueChanged<ProgressRange> onChanged;

  const _RangeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final values = ProgressRange.values;
    return Align(
      alignment: Alignment.centerLeft,
      child: ToggleButtons(
        borderRadius: BorderRadius.circular(12),
        isSelected: values.map((v) => v == value).toList(),
        onPressed: (idx) => onChanged(values[idx]),
        children: values
            .map((v) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(v.label),
                ))
            .toList(),
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  final VocalExercise exercise;
  final ExerciseStats stats;
  final VoidCallback onTap;

  const _ExerciseRow({
    required this.exercise,
    required this.stats,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final last = stats.lastScore?.toStringAsFixed(0) ?? '—';
    final avg = stats.averageRecent?.toStringAsFixed(0) ?? '—';
    final trendIcon = stats.trendSlope > 0.5
        ? Icons.trending_up
        : (stats.trendSlope < -0.5 ? Icons.trending_down : Icons.trending_flat);
    final trendColor = stats.trendSlope > 0.5
        ? Colors.green
        : (stats.trendSlope < -0.5 ? Colors.red : Colors.grey);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: onTap,
        leading: ExerciseIcon(iconKey: exercise.iconKey),
        title: Text(exercise.name),
        subtitle: Text('Last $last • Avg $avg • View history'),
        trailing: Icon(trendIcon, color: trendColor),
      ),
    );
  }
}
