import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/exercise_attempt.dart';
import '../../models/vocal_exercise.dart';
import '../../models/pitch_highway_difficulty.dart';
import '../../services/attempt_repository.dart';
import '../../routing/exercise_route_registry.dart';
import '../../ui/route_observer.dart';

class ExerciseProgressDetailScreen extends StatefulWidget {
  final VocalExercise exercise;

  const ExerciseProgressDetailScreen({super.key, required this.exercise});

  @override
  State<ExerciseProgressDetailScreen> createState() => _ExerciseProgressDetailScreenState();
}

class _ExerciseProgressDetailScreenState extends State<ExerciseProgressDetailScreen>
    with RouteAware {
  final AttemptRepository _attempts = AttemptRepository.instance;
  List<ExerciseAttempt> _exerciseAttempts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAttempts();
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
    _loadAttempts();
  }

  void _onAttemptsChanged() {
    if (mounted) {
      _loadAttempts();
    }
  }

  Future<void> _loadAttempts() async {
    await _attempts.refresh();
    final allAttempts = _attempts.cache
        .where((a) => a.exerciseId == widget.exercise.id)
        .toList()
      ..sort((a, b) {
        final aTime = a.completedAt ?? a.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.completedAt ?? b.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aTime.compareTo(bTime); // Oldest first for chronological display
      });
    if (mounted) {
      setState(() {
        _exerciseAttempts = allAttempts;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.exercise.name),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Exercise description
                if (widget.exercise.description.isNotEmpty) ...[
                  Text(
                    widget.exercise.description,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                ],
                // Bar graph
                Text(
                  'Performance Over Time',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 200,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: _exerciseAttempts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.bar_chart_outlined,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No sessions yet. Try your first one!',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : _LevelColoredBarChart(
                          attempts: _exerciseAttempts,
                        ),
                ),
                // Legend
                if (_exerciseAttempts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _DifficultyLegend(),
                ],
                const SizedBox(height: 32),
                // Start Exercise button
                ElevatedButton(
                  onPressed: _startExercise,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Start Exercise',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _startExercise() async {
    final opened = ExerciseRouteRegistry.open(
      context,
      widget.exercise.id,
    );
    if (!opened) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exercise not available')),
        );
      }
    }
  }
}

class _LevelColoredBarChart extends StatelessWidget {
  final List<ExerciseAttempt> attempts;

  const _LevelColoredBarChart({required this.attempts});

  Color _getColorForAttempt(ExerciseAttempt attempt) {
    // Extract level from pitchDifficulty or default to level 1
    int level = 1;
    if (attempt.pitchDifficulty != null) {
      final difficulty = pitchHighwayDifficultyFromName(attempt.pitchDifficulty!);
      if (difficulty != null) {
        level = pitchHighwayDifficultyLevel(difficulty);
      }
    }

    // Color by level: Beginner (1-2) = green, Intermediate (3-4) = blue, Advanced (5+) = purple
    if (level <= 2) {
      return Colors.green.shade400; // Beginner
    } else if (level <= 4) {
      return Colors.blue.shade400; // Intermediate
    } else {
      return Colors.purple.shade400; // Advanced
    }
  }

  @override
  Widget build(BuildContext context) {
    final scores = attempts.map((a) => a.overallScore).toList();
    final colors = attempts.map((a) => _getColorForAttempt(a)).toList();

    return CustomPaint(
      painter: _ColoredBarChartPainter(
        values: scores,
        colors: colors,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _ColoredBarChartPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;

  _ColoredBarChartPainter({
    required this.values,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final padding = 8.0;
    final chartWidth = size.width - padding * 2;
    final chartHeight = size.height - padding * 2;
    final barCount = values.length;
    final barWidth = chartWidth / math.max(1, barCount * 1.5);
    final gap = barWidth * 0.5;

    for (var i = 0; i < barCount; i++) {
      final v = values[i].clamp(0.0, 100.0) / 100.0;
      final barHeight = chartHeight * v;
      final x = padding + i * (barWidth + gap);
      final y = padding + chartHeight - barHeight;
      final paint = Paint()..color = colors[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(4),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ColoredBarChartPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.colors != colors;
  }
}

class _DifficultyLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LegendItem(
          color: Colors.green.shade400,
          label: 'Beginner',
        ),
        const SizedBox(width: 16),
        _LegendItem(
          color: Colors.blue.shade400,
          label: 'Intermediate',
        ),
        const SizedBox(width: 16),
        _LegendItem(
          color: Colors.purple.shade400,
          label: 'Advanced',
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[700],
              ),
        ),
      ],
    );
  }
}
