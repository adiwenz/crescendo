import 'package:flutter/material.dart';

import '../../models/exercise_take.dart';
import '../../services/exercise_progress_repository.dart';
import '../../models/exercise_plan.dart';
import 'exercise_progress_detail_screen.dart';

class ProgressHomeScreen extends StatefulWidget {
  const ProgressHomeScreen({super.key});

  @override
  State<ProgressHomeScreen> createState() => _ProgressHomeScreenState();
}

class _ProgressHomeScreenState extends State<ProgressHomeScreen> {
  final repo = ExerciseProgressRepository();
  Map<String, List<ExerciseTake>> data = {};
  bool _loading = true;
  final _catalog = [
    const ExercisePlan(
      id: 'c_major_scale',
      title: 'Scale',
      keyLabel: 'C Major',
      bpm: 120,
      gapSec: 0.1,
      notes: [],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await repo.loadAllTakes();
    setState(() {
      data = all;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey.shade50,
      appBar: AppBar(
        title: const Text('Progress'),
        backgroundColor: Colors.blueGrey.shade50,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: _catalog.map((exercise) {
                final takes = List<ExerciseTake>.from(data[exercise.id] ?? []);
                takes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
                final last = takes.isNotEmpty ? takes.first : null;
                final best = takes.isNotEmpty
                    ? takes.reduce((a, b) => a.score0to100 >= b.score0to100 ? a : b)
                    : null;
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    title: Text('${exercise.keyLabel} ${exercise.title}'),
                    subtitle: takes.isEmpty
                        ? const Text('No takes yet—do this exercise to see progress')
                        : Text('Last: ${last!.score0to100.toStringAsFixed(0)} • Best: ${best!.score0to100.toStringAsFixed(0)}'),
                    trailing: Icon(Icons.star, color: Colors.amber.withOpacity(takes.isEmpty ? 0.2 : 0.8)),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ExerciseProgressDetailScreen(
                            exerciseId: exercise.id,
                            title: '${exercise.keyLabel} ${exercise.title}',
                          ),
                        ),
                      );
                      _load();
                    },
                  ),
                );
              }).toList(),
            ),
    );
  }
}
