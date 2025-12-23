import 'package:flutter/material.dart';

import '../../data/seed_library.dart';
import '../../widgets/home/greeting_header.dart';
import '../../widgets/home/today_exercise_card.dart';
import '../../widgets/home/training_timeline_row.dart';
import '../explore/exercise_preview_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final warmup = seedExercisesFor('warmup').firstOrNull;
    final pitch = seedExercisesFor('pitch').firstOrNull;
    final lipTrills = seedExercisesFor('agility').firstOrNull;

    // Training timeline steps
    final trainingSteps = [
      TrainingTimelineRow(
        title: 'Warmup',
        statusText: 'Complete',
        status: TrainingStatus.completed,
        levelText: 'Level 1',
        onTap: warmup != null
            ? () => _openExercise(context, warmup.id, warmup.title)
            : null,
        isFirst: true,
      ),
      TrainingTimelineRow(
        title: 'Pitch Slides',
        statusText: 'In Progress',
        status: TrainingStatus.inProgress,
        progress: 0.35,
        levelText: 'Level 2',
        onTap: pitch != null
            ? () => _openExercise(context, pitch.id, pitch.title)
            : null,
      ),
      TrainingTimelineRow(
        title: 'Lip Trills',
        statusText: 'Next',
        status: TrainingStatus.next,
        levelText: 'Level 1',
        onTap: lipTrills != null
            ? () => _openExercise(context, lipTrills.id, lipTrills.title)
            : null,
        isLast: true,
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBFE), // Very light background
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Greeting Header
            const GreetingHeader(
              greeting: 'Good morning',
              subtitle: 'Let\'s train your voice',
            ),
            // Main Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 32),
                  // Continue Training Section
                  const Text(
                    'Continue Training',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1D1D1F),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ...trainingSteps,
                  const SizedBox(height: 40),
                  // Today's Exercises Section
                  const Text(
                    'Today\'s Exercises',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1D1D1F),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Exercise Cards (2 side-by-side)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (warmup != null)
                        TodayExerciseCard(
                          title: 'Warmup',
                          level: 'Level 1',
                          progress: 0.65,
                          icon: Icons.wb_sunny_outlined,
                          gradientStart: const Color(0xFFE8F4FD), // Soft blue
                          gradientEnd: const Color(0xFFD6EBF9),
                          onTap: () =>
                              _openExercise(context, warmup.id, warmup.title),
                        ),
                      if (warmup != null && pitch != null)
                        const SizedBox(width: 12),
                      if (pitch != null)
                        TodayExerciseCard(
                          title: 'Pitch Slides',
                          level: 'Level 2',
                          progress: 0.45,
                          icon: Icons.trending_up_outlined,
                          gradientStart: const Color(0xFFFFE5F0), // Soft pink
                          gradientEnd: const Color(0xFFFFD6E8),
                          onTap: () =>
                              _openExercise(context, pitch.id, pitch.title),
                        ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openExercise(BuildContext context, String id, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExercisePreviewScreen(exerciseId: id),
      ),
    );
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
