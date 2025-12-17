import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/exercise_attempt.dart';
import '../../models/exercise_category.dart';
import '../../models/progress_stats.dart';
import '../../models/vocal_exercise.dart';
import '../../services/exercise_repository.dart';
import '../../services/progress_service.dart';
import '../../services/progress_stats.dart';
import '../progress/progress_range.dart';
import '../widgets/exercise_icon.dart';
import '../widgets/progress_charts.dart';
import 'exercise_categories_screen.dart';
import 'progress_category_screen.dart';

class ProgressHomeScreen extends StatefulWidget {
  const ProgressHomeScreen({super.key});

  @override
  State<ProgressHomeScreen> createState() => _ProgressHomeScreenState();
}

class _ProgressHomeScreenState extends State<ProgressHomeScreen> {
  final ProgressService _progress = ProgressService();
  final ExerciseRepository _exerciseRepo = ExerciseRepository();
  ProgressRange _range = ProgressRange.days14;

  @override
  void initState() {
    super.initState();
    unawaited(_progress.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final categories = _exerciseRepo.getCategories();
    final exercises = _exerciseRepo.getExercises();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Progress'),
      ),
      body: StreamBuilder<ProgressSnapshot<ExerciseAttempt>>(
        stream: _progress.stream,
        initialData: _progress.snapshot(),
        builder: (context, snapshot) {
          final attempts = snapshot.data?.attempts ?? [];
          if (attempts.isEmpty) {
            return _EmptyProgressState(onStart: _openExercises);
          }
          final now = DateTime.now();
          final filtered = filterAttemptsByWindow(
            attempts,
            now: now,
            window: _range.window,
          );
          final overall = computeOverallStats(attempts: filtered);
          final weekAttempts = filterAttemptsByWindow(
            attempts,
            now: now,
            window: const Duration(days: 7),
          );
          final weekAvg = weekAttempts.isEmpty
              ? null
              : weekAttempts.map((a) => a.overallScore).reduce((a, b) => a + b) /
                  weekAttempts.length;
          final weekBest = weekAttempts.isEmpty
              ? null
              : weekAttempts.map((a) => a.overallScore).reduce((a, b) => a > b ? a : b);
          final sorted = List<ExerciseAttempt>.from(filtered)
            ..sort((a, b) => a.completedAt.compareTo(b.completedAt));
          final trendScores = sorted.map((a) => a.overallScore).toList();
          final trend = trendScores.length > 30
              ? trendScores.sublist(trendScores.length - 30)
              : trendScores;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _RangeToggle(
                value: _range,
                onChanged: (next) => setState(() => _range = next),
              ),
              const SizedBox(height: 12),
              _SummaryCard(
                weekCount: weekAttempts.length,
                weekAvg: weekAvg,
                weekBest: weekBest,
                overallScore: overall.score,
              ),
              const SizedBox(height: 16),
              Text('Overall trend', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Container(
                height: 140,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12),
                  ],
                ),
                child: trend.isEmpty
                    ? const Center(child: Text('No trend yet'))
                    : ProgressLineChart(values: trend),
              ),
              const SizedBox(height: 20),
              Text('Categories', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: categories.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  final category = categories[index];
                  final stats = computeCategoryStats(
                    categoryId: category.id,
                    exercises: exercises,
                    attempts: filtered,
                  );
                  return _CategoryCard(
                    category: category,
                    stats: stats,
                    onTap: () => _openCategory(category, exercises),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _openExercises() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExerciseCategoriesScreen()),
    );
  }

  void _openCategory(ExerciseCategory category, List<VocalExercise> exercises) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProgressCategoryScreen(
          category: category,
          exercises: exercises,
        ),
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

class _SummaryCard extends StatelessWidget {
  final int weekCount;
  final double? weekAvg;
  final double? weekBest;
  final double? overallScore;

  const _SummaryCard({
    required this.weekCount,
    required this.weekAvg,
    required this.weekBest,
    required this.overallScore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12)],
      ),
      child: Row(
        children: [
          ProgressScoreRing(score: overallScore),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This week', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Text('Sessions: $weekCount'),
                Text('Avg score: ${weekAvg?.toStringAsFixed(0) ?? '—'}'),
                Text('Best score: ${weekBest?.toStringAsFixed(0) ?? '—'}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final ExerciseCategory category;
  final CategoryStats stats;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.category,
    required this.stats,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scoreText = stats.score == null ? '—' : stats.score!.toStringAsFixed(0);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExerciseIcon(iconKey: category.iconKey, size: 22),
            const Spacer(),
            Text(category.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('$scoreText%',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            SizedBox(
              height: 24,
              child: stats.trendScores.isEmpty
                  ? const SizedBox.shrink()
                  : ProgressSparkline(values: stats.trendScores),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyProgressState extends StatelessWidget {
  final VoidCallback onStart;

  const _EmptyProgressState({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_graph, size: 48, color: Colors.black54),
            const SizedBox(height: 12),
            Text('Do an exercise to start tracking progress',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onStart,
              child: const Text('Browse exercises'),
            ),
          ],
        ),
      ),
    );
  }
}
