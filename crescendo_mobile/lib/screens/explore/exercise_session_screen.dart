import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/exercise.dart';
import '../../state/library_store.dart';
import '../../widgets/ballad_scaffold.dart';
import '../../widgets/ballad_buttons.dart';
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
    return BalladScaffold(
      title: widget.exercise.title,
      child: Center(
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: BalladPrimaryButton(
              label: 'Finish',
              isLoading: false, // Could add loading state if needed
              onPressed: _finished
                  ? null
                  : () async {
                      setState(() => _finished = true);
                      // Determine score
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
            )
        ),
      ),
    );
  }
}
