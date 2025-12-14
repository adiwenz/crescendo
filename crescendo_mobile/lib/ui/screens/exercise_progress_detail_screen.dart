import 'package:flutter/material.dart';

import '../../models/exercise_take.dart';
import '../../services/exercise_progress_repository.dart';
import '../widgets/progress_star_row.dart';
import '../widgets/score_line_chart.dart';

class ExerciseProgressDetailScreen extends StatefulWidget {
  final String exerciseId;
  final String title;
  const ExerciseProgressDetailScreen({super.key, required this.exerciseId, required this.title});

  @override
  State<ExerciseProgressDetailScreen> createState() => _ExerciseProgressDetailScreenState();
}

class _ExerciseProgressDetailScreenState extends State<ExerciseProgressDetailScreen> {
  final repo = ExerciseProgressRepository();
  List<ExerciseTake> takes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await repo.loadTakes(widget.exerciseId);
    setState(() {
      takes = data..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final best = takes.isNotEmpty
        ? takes.reduce((a, b) => a.score0to100 >= b.score0to100 ? a : b)
        : null;
    return Scaffold(
      backgroundColor: Colors.blueGrey.shade50,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.blueGrey.shade50,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : takes.isEmpty
              ? const Center(child: Text('No takes yet—complete this exercise to see progress'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Score history', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            ScoreLineChart(takes: takes),
                            const SizedBox(height: 8),
                            if (best != null)
                              Row(
                                children: [
                                  const Icon(Icons.star, color: Colors.amber),
                                  const SizedBox(width: 6),
                                  Text('Best: ${best.score0to100.toStringAsFixed(0)}'),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Recent takes', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            ...takes.reversed.take(10).map((t) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(t.createdAt.toLocal().toString().split('.').first),
                                  subtitle: ProgressStarRow(stars: t.stars),
                                  trailing: Text(t.score0to100.toStringAsFixed(0)),
                                ))
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
