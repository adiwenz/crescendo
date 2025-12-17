import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/exercise_attempt.dart';
import '../../models/progress_stats.dart';
import '../../models/vocal_exercise.dart';
import '../../services/progress_service.dart';
import '../../services/progress_stats.dart';
import '../widgets/exercise_icon.dart';
import '../widgets/progress_charts.dart';

enum AttemptRange { last10, last30, all }

extension AttemptRangeX on AttemptRange {
  String get label => switch (this) {
        AttemptRange.last10 => 'Last 10',
        AttemptRange.last30 => 'Last 30',
        AttemptRange.all => 'All',
      };
}

class ProgressExerciseScreen extends StatefulWidget {
  final VocalExercise exercise;

  const ProgressExerciseScreen({super.key, required this.exercise});

  @override
  State<ProgressExerciseScreen> createState() => _ProgressExerciseScreenState();
}

class _ProgressExerciseScreenState extends State<ProgressExerciseScreen> {
  final ProgressService _progress = ProgressService();
  AttemptRange _range = AttemptRange.last10;

  @override
  void initState() {
    super.initState();
    unawaited(_progress.refresh());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.exercise.name),
      ),
      body: StreamBuilder<ProgressSnapshot<ExerciseAttempt>>(
        stream: _progress.stream,
        initialData: _progress.snapshot(),
        builder: (context, snapshot) {
          final attempts = snapshot.data?.attempts ?? [];
          final exerciseAttempts = attempts
              .where((a) => a.exerciseId == widget.exercise.id)
              .toList()
            ..sort((a, b) => a.completedAt.compareTo(b.completedAt));
          final filtered = _applyRange(exerciseAttempts);
          final scores = filtered.map((a) => a.overallScore).toList();
          final stats = computeExerciseStats(
            exerciseId: widget.exercise.id,
            attempts: exerciseAttempts,
          );
          final lastAttempt = exerciseAttempts.isEmpty ? null : exerciseAttempts.last;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  ExerciseIcon(iconKey: widget.exercise.iconKey, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(widget.exercise.name,
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _AttemptRangeToggle(
                value: _range,
                onChanged: (next) => setState(() => _range = next),
              ),
              const SizedBox(height: 12),
              Container(
                height: 160,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12),
                  ],
                ),
                child: scores.isEmpty
                    ? const Center(child: Text('No attempts yet'))
                    : ProgressBarChart(values: scores),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _StatPill(label: 'Best', value: stats.bestScore?.toStringAsFixed(0) ?? '—'),
                  const SizedBox(width: 8),
                  _StatPill(label: 'Avg', value: stats.averageRecent?.toStringAsFixed(0) ?? '—'),
                  const SizedBox(width: 8),
                  _StatPill(label: 'Last', value: stats.lastScore?.toStringAsFixed(0) ?? '—'),
                ],
              ),
              const SizedBox(height: 16),
              if (lastAttempt?.subScores != null && lastAttempt!.subScores!.isNotEmpty) ...[
                Text('Sub-scores', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: lastAttempt.subScores!.entries
                      .map((e) => Chip(label: Text('${e.key}: ${e.value.toStringAsFixed(0)}')))
                      .toList(),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  List<ExerciseAttempt> _applyRange(List<ExerciseAttempt> attempts) {
    if (_range == AttemptRange.all) return attempts;
    final limit = _range == AttemptRange.last10 ? 10 : 30;
    if (attempts.length <= limit) return attempts;
    return attempts.sublist(attempts.length - limit);
  }
}

class _AttemptRangeToggle extends StatelessWidget {
  final AttemptRange value;
  final ValueChanged<AttemptRange> onChanged;

  const _AttemptRangeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final values = AttemptRange.values;
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

class _StatPill extends StatelessWidget {
  final String label;
  final String value;

  const _StatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}
