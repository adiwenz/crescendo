import 'package:flutter/material.dart';

import '../../data/seed_library.dart';
import '../../widgets/home/exercise_mini_card.dart';
import '../../widgets/home/greeting_header.dart';
import '../../widgets/home/illustrated_tile.dart';
import '../../widgets/home/illustration_assets.dart';
import '../../widgets/home/soft_card.dart';
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
        backgroundImagePath: IllustrationAssets.warmupWatermark,
        onTap: warmup != null
            ? () => _openExercise(context, warmup.id, warmup.title)
            : null,
      ),
      TrainingTimelineCard(
        title: 'Pitch Slides',
        subtitle: 'In Progress • Level 2',
        status: TrainingStatus.inProgress,
        progress: 0.72,
        trailingText: 'Level 2',
        backgroundImagePath: IllustrationAssets.pitchWatermark,
        onTap: pitch != null
            ? () => _openExercise(context, pitch.id, pitch.title)
            : null,
      ),
      TrainingTimelineCard(
        title: 'Lip Trills',
        subtitle: 'Next • Level 2',
        status: TrainingStatus.next,
        trailingText: 'Level 2',
        backgroundImagePath: IllustrationAssets.lipTrillsWatermark,
        onTap: lipTrills != null
            ? () => _openExercise(context, lipTrills.id, lipTrills.title)
            : null,
      ),
    ];

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFFFF4F6), // Single-hue blush top
              const Color(0xFFFBEAEC), // Single-hue blush bottom
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
                    // Category tiles (Warmup / Pitch / Agility)
                    Row(
                      children: [
                        IllustratedTile(
                          label: 'Warmup',
                          subtitle: '3–5 min',
                          illustrationPath: IllustrationAssets.warmup,
                          backgroundColor: IllustrationAssets.warmupColor,
                          onTap: warmup != null
                              ? () => _openExercise(
                                  context, warmup.id, warmup.title)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        IllustratedTile(
                          label: 'Pitch',
                          subtitle: '5–10 min',
                          illustrationPath: IllustrationAssets.pitch,
                          backgroundColor: IllustrationAssets.pitchColor,
                          onTap: pitch != null
                              ? () =>
                                  _openExercise(context, pitch.id, pitch.title)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        IllustratedTile(
                          label: 'Agility',
                          subtitle: '5–10 min',
                          illustrationPath: IllustrationAssets.agility,
                          backgroundColor: IllustrationAssets.agilityColor,
                          onTap: lipTrills != null
                              ? () => _openExercise(
                                  context, lipTrills.id, lipTrills.title)
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
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
                    // Continue Training Card (single large card with list inside)
                    SoftCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          TrainingTimeline(cards: trainingCards),
                        ],
                      ),
                    ),
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
                          backgroundImagePath:
                              IllustrationAssets.warmupExercise,
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
                          backgroundImagePath: IllustrationAssets.pitchAccuracy,
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
