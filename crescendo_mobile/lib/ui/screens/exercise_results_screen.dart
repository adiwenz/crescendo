import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/exercise_plan.dart';
import '../../models/exercise_take.dart';
import '../../models/pitch_frame.dart';
import '../../services/exercise_repository.dart';
import '../../services/exercise_progress_repository.dart';
import '../../services/progress_service.dart';
import '../widgets/progress_star_row.dart';
import 'hold_stability_screen.dart';
import 'progress_exercise_screen.dart';

class ExerciseResultsScreen extends StatefulWidget {
  final ExerciseTake take;
  final String exerciseId;
  final ExercisePlan plan;
  final List<PitchFrame> frames;

  const ExerciseResultsScreen({
    super.key,
    required this.take,
    required this.exerciseId,
    required this.plan,
    required this.frames,
  });

  @override
  State<ExerciseResultsScreen> createState() => _ExerciseResultsScreenState();
}

class _ExerciseResultsScreenState extends State<ExerciseResultsScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  final repo = ExerciseProgressRepository();
  final ProgressService _progress = ProgressService();
  final ExerciseRepository _exerciseRepo = ExerciseRepository();
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _scale = Tween<double>(begin: 0.8, end: 1.05)
        .chain(CurveTween(curve: Curves.elasticOut))
        .animate(_controller);
    _saveTake();
    _controller.forward();
  }

  Future<void> _saveTake() async {
    if (_saved) return;
    await repo.addTake(widget.take);
    final exercise =
        _exerciseRepo.getExercises().where((e) => e.id == widget.exerciseId).toList();
    final exerciseDef = exercise.isNotEmpty ? exercise.first : null;
    if (exerciseDef != null) {
      final subs = <String, double>{
        'onPitch': widget.take.onPitchPct,
      };
      if (widget.take.avgCentsAbs != null) {
        subs['avgCentsAbs'] = widget.take.avgCentsAbs!;
      }
      final attempt = _progress.buildAttempt(
        exerciseId: exerciseDef.id,
        categoryId: exerciseDef.categoryId,
        startedAt: widget.take.createdAt,
        completedAt: widget.take.createdAt,
        overallScore: widget.take.score0to100,
        subScores: subs,
      );
      unawaited(_progress.saveAttempt(attempt));
    }
    setState(() => _saved = true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final score = widget.take.score0to100.toStringAsFixed(0);
    return Scaffold(
      backgroundColor: Colors.blueGrey.shade50,
      appBar: AppBar(
        title: const Text('Exercise Results'),
        backgroundColor: Colors.blueGrey.shade50,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.lightBlueAccent, Colors.blueAccent.shade200]),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.25), blurRadius: 16)],
                ),
                child: Column(
                  children: [
                    const Text('Score', style: TextStyle(color: Colors.white70)),
                    Text(score,
                        style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ScaleTransition(
                scale: _scale,
                child: ProgressStarRow(stars: widget.take.stars),
              ),
              const SizedBox(height: 8),
              Text(
                widget.take.stars >= 4 ? 'Nice! Your pitch is locking in 🎯' : 'Keep going—you got this! ✨',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, 'retry'),
                    child: const Text('Try again'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HoldStabilityScreen(
                            plan: widget.plan,
                            frames: widget.frames,
                            previousHoldMetrics: null,
                          ),
                        ),
                      );
                    },
                    child: const Text('Hold stability'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final exercise =
                          _exerciseRepo.getExercises().where((e) => e.id == widget.exerciseId).toList();
                      if (exercise.isNotEmpty) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProgressExerciseScreen(exercise: exercise.first),
                          ),
                        );
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    child: const Text('View progress'),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
