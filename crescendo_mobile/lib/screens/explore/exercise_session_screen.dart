import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/exercise.dart';
import '../../state/library_store.dart';
import 'results_screen.dart';

class ExerciseSessionScreen extends StatefulWidget {
  final Exercise exercise;

  const ExerciseSessionScreen({super.key, required this.exercise});

  @override
  State<ExerciseSessionScreen> createState() => _ExerciseSessionScreenState();
}

class _ExerciseSessionScreenState extends State<ExerciseSessionScreen> {
  bool _finished = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.exercise.title)),
      body: Center(
        child: ElevatedButton(
          onPressed: _finished
              ? null
              : () async {
                  setState(() => _finished = true);
                  final score = 70 + Random().nextInt(29);
                  libraryStore.markCompleted(widget.exercise.id, score: score);
                  if (!mounted) return;
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ResultsScreen(score: score.toDouble(), exerciseId: widget.exercise.id),
                    ),
                  );
                },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Text('Finish', style: TextStyle(fontSize: 18)),
          ),
        ),
      ),
    );
  }
}
