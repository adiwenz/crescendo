import 'package:flutter/material.dart';

import '../../data/seed_library.dart';
import '../../widgets/home/exercise_mini_card.dart';
import '../../widgets/home/greeting_header.dart';
import '../../widgets/home/quick_action_card.dart';
import '../../widgets/home/training_timeline.dart';
import '../../widgets/home/training_timeline_card.dart';
import '../explore/exercise_preview_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final warmup = seedExercisesFor('warmup').firstOrNull;
    final pitch = seedExercisesFor('pitch').firstOrNull;
    final lipTrills = seedExercisesFor('agility').firstOrNull;

    // Training timeline cards
    final trainingCards = [
      TrainingTimelineCard(
        title: 'Warmup',
        subtitle: 'Complete',
        status: TrainingStatus.completed,
        cardTintColor: const Color(0xFF8FC9A8).withOpacity(0.4), // Green
        singingIcon: Icons.mic_external_on,
        onTap: warmup != null
            ? () => _openExercise(context, warmup.id, warmup.title)
            : null,
      ),
      TrainingTimelineCard(
        title: 'Pitch Slides',
        subtitle: 'In Progress • Level 2',
        status: TrainingStatus.inProgress,
        progress: 0.72,
        cardTintColor:
            const Color(0xFF8FC9A8).withOpacity(0.25), // Lighter green
        trailingText: 'Level 2',
        singingIcon: Icons.trending_up,
        onTap: pitch != null
            ? () => _openExercise(context, pitch.id, pitch.title)
            : null,
      ),
      TrainingTimelineCard(
        title: 'Lip Trills',
        subtitle: 'Next • Level 2',
        status: TrainingStatus.next,
        cardTintColor: const Color(0xFFFFB88C).withOpacity(0.4), // Orange
        trailingText: 'Level 2',
        singingIcon: Icons.waves,
        onTap: lipTrills != null
            ? () => _openExercise(context, lipTrills.id, lipTrills.title)
            : null,
      ),
    ];

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF7FD1B9).withOpacity(0.08), // Mint
              const Color(0xFFF1D27A).withOpacity(0.06), // Butter yellow
            ],
          ),
        ),
        child: SafeArea(
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
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    // Recents and Favorites Cards
                    Row(
                      children: [
                        QuickActionCard(
                          title: 'Recents',
                          icon: Icons.history_outlined,
                          cardTintColor: const Color(0xFFF1D27A)
                              .withOpacity(0.3), // Butter yellow
                          onTap: () {},
                        ),
                        const SizedBox(width: 12),
                        QuickActionCard(
                          title: 'Favorites',
                          icon: Icons.favorite_outline,
                          cardTintColor: const Color(0xFFFFB88C)
                              .withOpacity(0.3), // Soft orange
                          onTap: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    // Continue Training Section Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Continue Training',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2E2E2E),
                          ),
                        ),
                        InkWell(
                          onTap: () {},
                          child: const Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: Color(0xFFA5A5A5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Training Timeline
                    TrainingTimeline(cards: trainingCards),
                    const SizedBox(height: 40),
                    // Today's Exercises Section Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Today\'s Exercises',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2E2E2E),
                          ),
                        ),
                        InkWell(
                          onTap: () {},
                          child: const Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: Color(0xFFA5A5A5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Exercise Cards (2 side-by-side)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExerciseMiniCard(
                          title: 'Warmup',
                          level: 'Level 1',
                          progress: 0.65,
                          cardTintColor: const Color(0xFFFFB88C)
                              .withOpacity(0.4), // Orange
                          watermarkIcon: Icons.local_fire_department,
                          onTap: warmup != null
                              ? () => _openExercise(
                                  context, warmup.id, warmup.title)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        ExerciseMiniCard(
                          title: 'Build pitch accuracy',
                          level: 'Level 1',
                          progress: 0.45,
                          cardTintColor: const Color(0xFFF1D27A)
                              .withOpacity(0.4), // Yellow
                          watermarkIcon: Icons.graphic_eq,
                          onTap: pitch != null
                              ? () =>
                                  _openExercise(context, pitch.id, pitch.title)
                              : null,
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
