import 'package:flutter/material.dart';

import '../../data/seed_library.dart';
import '../../services/simple_progress_repository.dart';
import '../../state/library_store.dart';
import '../../widgets/progress/metric_pill.dart';
import '../../widgets/progress/progress_bar_row.dart';
import '../../widgets/progress/recent_activity_row.dart';
import '../../widgets/progress/sparkline_card.dart';

class ProgressHomeScreen extends StatefulWidget {
  const ProgressHomeScreen({super.key});

  @override
  State<ProgressHomeScreen> createState() => _ProgressHomeScreenState();
}

class _ProgressHomeScreenState extends State<ProgressHomeScreen> {
  final SimpleProgressRepository _repo = SimpleProgressRepository();

  @override
  Widget build(BuildContext context) {
    final summary = _repo.buildSummary();
    final categories = seedLibraryCategories();
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
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
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
          SparklineCard(
            title: 'Trend (last 7)',
            values: summary.trendScores.isEmpty ? [0] : summary.trendScores,
          ),
          const SizedBox(height: 16),
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
                  ...categories.map((c) {
                    final pct = summary.categoryPercents[c.id] ?? 0.0;
                    final exes = seedExercisesFor(c.id);
                    final completedCount = exes.where((e) => libraryStore.completedExerciseIds.contains(e.id)).length;
                    final subtitle = '${completedCount}/${exes.length} completed';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ProgressBarRow(
                        title: c.title,
                        subtitle: subtitle,
                        percent: pct,
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recent Activity', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (summary.recent.isEmpty)
                    Text('No activity yet', style: Theme.of(context).textTheme.bodyMedium)
                  else
                    ...summary.recent.take(5).map((a) {
                      final d = a.date;
                      final date =
                          '${_month(d.month)} ${d.day}, ${d.hour % 12 == 0 ? 12 : d.hour % 12}:${d.minute.toString().padLeft(2, '0')}${d.hour >= 12 ? 'pm' : 'am'}';
                      final scoreLabel = a.score == null ? '--' : a.score.toString();
                      return RecentActivityRow(
                        title: a.exerciseId,
                        dateLabel: date,
                        scoreLabel: scoreLabel,
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _month(int m) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (m < 1 || m > 12) return '';
    return names[m - 1];
  }
}
