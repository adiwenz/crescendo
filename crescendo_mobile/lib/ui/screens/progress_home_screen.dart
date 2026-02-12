import 'package:flutter/material.dart';

import '../../services/simple_progress_repository.dart';
import '../../widgets/progress/metric_pill.dart';
import '../../widgets/progress/progress_bar_row.dart';
import '../../services/attempt_repository.dart';
import '../../ui/widgets/progress_charts.dart';
import '../../models/exercise_attempt.dart';
import '../../services/exercise_repository.dart';
import '../../ui/route_observer.dart';
import '../../widgets/ballad_scaffold.dart';
import '../../theme/ballad_theme.dart';
import '../../widgets/frosted_panel.dart';
import 'category_progress_screen.dart';

class ProgressHomeScreen extends StatefulWidget {
  const ProgressHomeScreen({super.key});

  @override
  State<ProgressHomeScreen> createState() => _ProgressHomeScreenState();
}

enum _TrendFilter { day, week, month }

class _ProgressHomeScreenState extends State<ProgressHomeScreen> with RouteAware {
  final SimpleProgressRepository _repo = SimpleProgressRepository();
  Future<ProgressSummary>? _future;
  late final ProgressSummary _initial;
  final AttemptRepository _attempts = AttemptRepository.instance;
  int _lastRevision = -1;
  _TrendFilter _selectedFilter = _TrendFilter.week;

  @override
  void initState() {
    super.initState();
    _lastRevision = _attempts.revision;
    // Build initial summary synchronously from what's already in memory
    _initial = _repo.buildSummaryFromCache();
    
    // Only trigger a full refresh if not already loaded
    if (!_attempts.cache.isNotEmpty) {
      _future = _loadSummary();
    } else {
      _future = Future.value(_initial);
    }
    
    _attempts.addListener(_onAttemptsChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _attempts.removeListener(_onAttemptsChanged);
    super.dispose();
  }

  @override
  void didPopNext() {
    // When returning to this screen, refresh data from database
    // BUT do it after the current frame to avoid blocking navigation animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _attempts.refresh().then((_) {
          if (mounted) {
            setState(() {
              _lastRevision = _attempts.revision;
              _future = _loadSummary();
            });
          }
        });
      }
    });
  }

  void _onAttemptsChanged() {
    if (!mounted) return;
    debugPrint('[ProgressHomeScreen] attempts changed, revision=${_attempts.revision}');
    // Only rebuild if the revision actually changed (prevents unnecessary rebuilds)
    if (_attempts.revision == _lastRevision) return;
    _lastRevision = _attempts.revision;
    
    // Debounce summary build if multiple attempts hit at once
    setState(() {
      _future = _loadSummary();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BalladScaffold(
      title: 'Progress',
      child: FutureBuilder<ProgressSummary>(
        future: _future,
        initialData: _initial,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null) {
            return const Center(child: CircularProgressIndicator());
          }
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
          final dailyStats = _computeDailyStats(_attempts.cache, _selectedFilter);
          
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Your practice over time',
                style: BalladTheme.bodyMedium.copyWith(color: BalladTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              // Today's stats card
              FrostedPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Today', style: BalladTheme.titleMedium),
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
              const SizedBox(height: 16),
              // Line graph: Trend
              FrostedPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Trend',
                          style: BalladTheme.titleMedium,
                        ),
                        // Filter buttons
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _FilterChip(
                              label: 'Day',
                              selected: _selectedFilter == _TrendFilter.day,
                              onTap: () => setState(() => _selectedFilter = _TrendFilter.day),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'Week',
                              selected: _selectedFilter == _TrendFilter.week,
                              onTap: () => setState(() => _selectedFilter = _TrendFilter.week),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'Month',
                              selected: _selectedFilter == _TrendFilter.month,
                              onTap: () => setState(() => _selectedFilter = _TrendFilter.month),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 120,
                      child: dailyStats.avgScores.isEmpty
                          ? Center(
                              child: Text(
                                'No data yet',
                                style: BalladTheme.bodySmall.copyWith(color: BalladTheme.textSecondary),
                              ),
                            )
                          : ProgressBarChart(values: dailyStats.avgScores),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Primary category progress list
              FrostedPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Category Progress', style: BalladTheme.titleMedium),
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

  _DailyStats _computeDailyStats(List<ExerciseAttempt> attempts, _TrendFilter filter) {
    if (attempts.isEmpty) {
      return _DailyStats(avgScores: [], exerciseCounts: []);
    }

    // Filter attempts by time window
    final now = DateTime.now();
    final cutoff = switch (filter) {
      _TrendFilter.day => DateTime(now.year, now.month, now.day), // Today since midnight
      _TrendFilter.week => now.subtract(const Duration(days: 7)),
      _TrendFilter.month => now.subtract(const Duration(days: 30)),
    };

    final filteredAttempts = attempts.where((a) {
      final date = a.completedAt ?? a.startedAt;
      if (date == null) return false;
      return date.isAfter(cutoff);
    }).toList();

    if (filteredAttempts.isEmpty) {
      return _DailyStats(avgScores: [], exerciseCounts: []);
    }

    // Sort by time (oldest first)
    filteredAttempts.sort((a, b) {
      final aTime = a.completedAt ?? a.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.completedAt ?? b.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aTime.compareTo(bTime);
    });

    if (filter == _TrendFilter.day) {
      // Day filter: each exercise attempt is a point
      final scores = filteredAttempts
          .map((a) => a.overallScore)
          .where((s) => s > 0)
          .toList();
      return _DailyStats(avgScores: scores, exerciseCounts: []);
    } else {
      // Week/Month filter: average score per day (one point per day)
      // Group attempts by date
      final byDate = <DateTime, List<ExerciseAttempt>>{};
      for (final attempt in filteredAttempts) {
        final date = attempt.completedAt ?? attempt.startedAt;
        if (date == null) continue;
        final dateOnly = DateTime(date.year, date.month, date.day);
        byDate.putIfAbsent(dateOnly, () => []).add(attempt);
      }

      // Get all dates in the range, sorted
      final dates = byDate.keys.toList()..sort();

      final avgScores = <double>[];
      for (final date in dates) {
        final dayAttempts = byDate[date]!;
        final scores = dayAttempts.map((a) => a.overallScore).where((s) => s > 0).toList();
        if (scores.isNotEmpty) {
          final avg = scores.reduce((a, b) => a + b) / scores.length;
          avgScores.add(avg);
        }
      }

      return _DailyStats(avgScores: avgScores, exerciseCounts: []);
    }
  }
}

class _DailyStats {
  final List<double> avgScores;
  final List<double> exerciseCounts;

  _DailyStats({required this.avgScores, required this.exerciseCounts});
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? BalladTheme.accentPurple : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? BalladTheme.accentPurple : Colors.white24,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: BalladTheme.bodySmall.copyWith(
                color: selected ? Colors.white : BalladTheme.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
        ),
      ),
    );
  }
}
