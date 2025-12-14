import 'package:flutter/material.dart';

import '../../models/exercise_take.dart';
import '../../services/exercise_progress_repository.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await repo.loadAll();
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
          : data.isEmpty
              ? const Center(child: Text('Complete an exercise to see progress'))
              : ListView(
                  children: data.entries.map((entry) {
                    final takes = entry.value;
                    takes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
                    final last = takes.first;
                    final best = takes.reduce((a, b) => a.score0to100 >= b.score0to100 ? a : b);
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: ListTile(
                        title: Text(last.title),
                        subtitle: Text('Last: ${last.score0to100.toStringAsFixed(0)} • Best: ${best.score0to100.toStringAsFixed(0)}'),
                        trailing: Icon(Icons.star, color: Colors.amber.withOpacity(0.8)),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ExerciseProgressDetailScreen(
                              exerciseId: entry.key,
                              title: last.title,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
    );
  }
}
