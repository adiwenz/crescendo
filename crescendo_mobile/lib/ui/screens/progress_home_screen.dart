import 'package:flutter/material.dart';

import '../../services/simple_progress_repository.dart';
import '../../widgets/progress/metric_pill.dart';
import '../../widgets/progress/progress_bar_row.dart';
import '../../services/attempt_repository.dart';
import '../../ui/widgets/progress_charts.dart';
import '../../models/exercise_attempt.dart';
import '../../services/exercise_repository.dart';
import 'category_progress_screen.dart';

class ProgressHomeScreen extends StatefulWidget {
  const ProgressHomeScreen({super.key});

  @override
  State<ProgressHomeScreen> createState() => _ProgressHomeScreenState();
}

class _ProgressHomeScreenState extends State<ProgressHomeScreen> {
  final SimpleProgressRepository _repo = SimpleProgressRepository();
  Future<ProgressSummary>? _future;
  late final ProgressSummary _initial;
  final AttemptRepository _attempts = AttemptRepository.instance;

  @override
  void initState() {
    super.initState();
    _initial = _repo.buildSummaryFromCache();
    _future = _loadSummary();
    _attempts.addListener(_onAttemptsChanged);
  }

  @override
  void dispose() {
    _attempts.removeListener(_onAttemptsChanged);
    super.dispose();
  }

  void _onAttemptsChanged() {
    if (!mounted) return;
    setState(() {
      _future = _loadSummary();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Progress'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Your practice over time',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            ),
          ),
        ),
      ),
      body: FutureBuilder<ProgressSummary>(
        future: _future,
        initialData: _initial,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Error loading progress'),
                  const SizedBox(height: 8),
                  Text('${snapshot.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => setState(() {
                      _future = _loadSummary();
                    }),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          final summary = snapshot.data!;
          final dailyStats = _computeDailyStats(_attempts.cache);
          
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // Today's stats card
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Today', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: MetricPill(label: 'Practice time', value: '—')),
                          const SizedBox(width: 12),
                          Expanded(child: MetricPill(label: 'Completed', value: '${summary.completedToday}')),
                          const SizedBox(width: 12),
                          Expanded(child: MetricPill(label: 'Avg score', value: summary.avgScore.isNaN ? '—' : '${summary.avgScore.toStringAsFixed(0)}%')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Line graph: Trend
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Trend',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 120,
                        child: dailyStats.avgScores.isEmpty
                            ? Center(
                                child: Text(
                                  'No data yet',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.grey[600],
                                      ),
                                ),
                              )
                            : ProgressLineChart(values: dailyStats.avgScores),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Primary category progress list
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Category Progress', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      ...summary.categories.map((c) {
                        final subtitle = '${c.completedCount}/${c.totalCount} completed';
                        final widgetRow = ProgressBarRow(
                          title: c.title,
                          subtitle: subtitle,
                          percent: c.percent,
                        );
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              final repo = ExerciseRepository();
                              final category = repo.getCategories().firstWhere(
                                (cat) => cat.id == c.categoryId,
                                orElse: () {
                                  // If category not found, try to find by title match
                                  final byTitle = repo.getCategories().where(
                                    (cat) => cat.title.toLowerCase() == c.title.toLowerCase(),
                                  ).toList();
                                  if (byTitle.isNotEmpty) {
                                    return byTitle.first;
                                  }
                                  // Last resort: return first category
                                  return repo.getCategories().first;
                                },
                              );
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CategoryProgressScreen(category: category),
                                ),
                              );
                            },
                            child: widgetRow,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<ProgressSummary> _loadSummary() async {
    try {
      return await _repo.buildSummary();
    } catch (e, st) {
      debugPrint('Progress load error: $e\n$st');
      rethrow;
    }
  }

  _DailyStats _computeDailyStats(List<ExerciseAttempt> attempts) {
    if (attempts.isEmpty) {
      return _DailyStats(avgScores: [], exerciseCounts: []);
    }

    // Group attempts by date
    final byDate = <DateTime, List<ExerciseAttempt>>{};
    for (final attempt in attempts) {
      final date = attempt.completedAt ?? attempt.startedAt;
      if (date == null) continue;
      final dateOnly = DateTime(date.year, date.month, date.day);
      byDate.putIfAbsent(dateOnly, () => []).add(attempt);
    }

    // Get last 30 days
    final now = DateTime.now();
    final dates = <DateTime>[];
    for (var i = 29; i >= 0; i--) {
      dates.add(DateTime(now.year, now.month, now.day).subtract(Duration(days: i)));
    }

    final avgScores = <double>[];
    final exerciseCounts = <double>[];

    for (final date in dates) {
      final dayAttempts = byDate[date] ?? [];
      if (dayAttempts.isEmpty) {
        avgScores.add(0);
        exerciseCounts.add(0);
      } else {
        // Average score for the day
        final scores = dayAttempts.map((a) => a.overallScore).toList();
        final avg = scores.reduce((a, b) => a + b) / scores.length;
        avgScores.add(avg);
        // Count of exercises (unique exerciseIds)
        final uniqueExercises = dayAttempts.map((a) => a.exerciseId).toSet();
        exerciseCounts.add(uniqueExercises.length.toDouble());
      }
    }

    return _DailyStats(avgScores: avgScores, exerciseCounts: exerciseCounts);
  }
}

class _DailyStats {
  final List<double> avgScores;
  final List<double> exerciseCounts;

  _DailyStats({required this.avgScores, required this.exerciseCounts});
}
