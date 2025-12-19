import 'package:flutter/material.dart';

import '../../services/simple_progress_repository.dart';
import '../../widgets/progress/metric_pill.dart';
import '../../widgets/progress/progress_bar_row.dart';
import '../../widgets/progress/recent_activity_row.dart';
import '../../widgets/progress/sparkline_card.dart';
import 'progress_category_detail_screen.dart';
import '../../services/attempt_repository.dart';

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
          return ListView(
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
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CategoryProgressDetailScreen(categoryId: c.categoryId),
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
                          final date = _formatDate(d);
                          final scoreLabel = a.score == null ? '--' : a.score.toString();
                          return RecentActivityRow(
                            title: a.exerciseTitle,
                            subtitle: a.categoryTitle,
                            dateLabel: date,
                            scoreLabel: scoreLabel,
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

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(d.year, d.month, d.day);
    if (dateOnly == today) return 'Today';
    if (dateOnly == yesterday) return 'Yesterday';
    return '${_month(d.month)} ${d.day}';
  }

  String _month(int m) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (m < 1 || m > 12) return '';
    return names[m - 1];
  }

  Future<ProgressSummary> _loadSummary() async {
    try {
      return await _repo.buildSummary();
    } catch (e, st) {
      debugPrint('Progress load error: $e\n$st');
      rethrow;
    }
  }
}
