import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/seed_library.dart';
import '../../widgets/home/checklist_row.dart';
import '../../widgets/home/horizontal_item_card.dart';
import '../../widgets/home/illustration_assets.dart';
import '../../widgets/home/soft_pill_card.dart';
import '../explore/exercise_preview_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final warmup = seedExercisesFor('warmup').firstOrNull;
    final pitch = seedExercisesFor('pitch').firstOrNull;
    final lipTrills = seedExercisesFor('agility').firstOrNull;
    final stability = seedExercisesFor('stability').firstOrNull;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light, // White status bar content
      child: Scaffold(
        body: Container(
          color: Colors.white, // White background
          child: SafeArea(
            bottom: false,
            top:
                false, // Remove top safe area so header extends into status bar
            child: Column(
              children: [
                // Mint green header (extends into status bar)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 16,
                    left: 20,
                    right: 20,
                    bottom: 20,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFF7FD1B9), // Mint green
                  ),
                  child: const Text(
                    'Today',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                // Main content
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      // Main checklist content
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Today's Exercises section
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 8, top: 24),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF4A3C4)
                                      .withOpacity(0.25), // Blush pink pill
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFF4A3C4)
                                          .withOpacity(0.15),
                                      blurRadius: 12,
                                      spreadRadius: 0,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Text(
                                  'Today\'s Exercises',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF2E2E2E),
                                  ),
                                ),
                              ),
                            ),
                            // Today's Exercises timeline with vertical line and checkmarks
                            Stack(
                              children: [
                                // Vertical connecting line
                                Positioned(
                                  left: 12,
                                  top: 12,
                                  bottom: 12,
                                  child: Container(
                                    width: 2,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE6E1DC),
                                      borderRadius: BorderRadius.circular(1),
                                    ),
                                  ),
                                ),
                                // Exercise cards with checkmarks
                                Column(
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Checkmark circle area
                                        SizedBox(
                                          width: 28,
                                          child: _ExerciseCheckmark(
                                              isCompleted: true),
                                        ),
                                        const SizedBox(width: 16),
                                        // Card
                                        Expanded(
                                          child: SoftPillCard(
                                            onTap: warmup != null
                                                ? () => _openExercise(context,
                                                    warmup.id, warmup.title)
                                                : null,
                                            child: ChecklistRow(
                                              title: 'Warmup',
                                              subtitle: 'Level 1',
                                              icon: Icons.fitness_center,
                                              accentColor: IllustrationAssets
                                                  .warmupColor,
                                              isCompleted: true,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Checkmark circle area
                                        SizedBox(
                                          width: 28,
                                          child: _ExerciseCheckmark(
                                              isCompleted: false),
                                        ),
                                        const SizedBox(width: 16),
                                        // Card
                                        Expanded(
                                          child: SoftPillCard(
                                            onTap: pitch != null
                                                ? () => _openExercise(context,
                                                    pitch.id, pitch.title)
                                                : null,
                                            child: ChecklistRow(
                                              title: 'Build pitch accuracy',
                                              subtitle: 'Level 1',
                                              icon: Icons.music_note,
                                              accentColor:
                                                  IllustrationAssets.pitchColor,
                                              isCompleted: false,
                                              trailing: const Icon(
                                                Icons.chevron_right,
                                                size: 20,
                                                color: Color(0xFFA5A5A5),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Checkmark circle area
                                        SizedBox(
                                          width: 28,
                                          child: _ExerciseCheckmark(
                                              isCompleted: false),
                                        ),
                                        const SizedBox(width: 16),
                                        // Card
                                        Expanded(
                                          child: SoftPillCard(
                                            onTap: stability != null
                                                ? () => _openExercise(
                                                    context,
                                                    stability.id,
                                                    stability.title)
                                                : null,
                                            child: ChecklistRow(
                                              title: 'Range Building',
                                              subtitle: 'Level 1',
                                              icon: Icons.trending_up,
                                              accentColor: IllustrationAssets
                                                  .agilityColor,
                                              isCompleted: false,
                                              trailing: const Icon(
                                                Icons.chevron_right,
                                                size: 20,
                                                color: Color(0xFFA5A5A5),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            // Try Next section
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1D27A)
                                      .withOpacity(0.25), // Butter yellow pill
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFF1D27A)
                                          .withOpacity(0.15),
                                      blurRadius: 12,
                                      spreadRadius: 0,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.star,
                                      size: 18,
                                      color: Color(0xFFF1D27A), // Butter yellow
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Try Next',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF2E2E2E),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(
                              height: 120,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.only(left: 0),
                                children: [
                                  HorizontalItemCard(
                                    title: 'Pitch Slides',
                                    subtitle: 'Level 2',
                                    icon: Icons.music_note,
                                    accentColor: const Color(
                                        0xFFF1D27A), // Butter yellow
                                    onTap: pitch != null
                                        ? () => _openExercise(
                                            context, pitch.id, pitch.title)
                                        : null,
                                  ),
                                  HorizontalItemCard(
                                    title: 'Lip Trills',
                                    subtitle: 'Level 2',
                                    icon: Icons.speed,
                                    accentColor: const Color(
                                        0xFFF1D27A), // Butter yellow
                                    onTap: lipTrills != null
                                        ? () => _openExercise(context,
                                            lipTrills.id, lipTrills.title)
                                        : null,
                                  ),
                                  HorizontalItemCard(
                                    title: 'Range Building',
                                    subtitle: 'Level 1',
                                    icon: Icons.trending_up,
                                    accentColor: const Color(
                                        0xFFF1D27A), // Butter yellow
                                    onTap: warmup != null
                                        ? () => _openExercise(
                                            context, warmup.id, warmup.title)
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            // Continue Training section
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7FD1B9)
                                      .withOpacity(0.25), // Mint/teal pill
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF7FD1B9)
                                          .withOpacity(0.15),
                                      blurRadius: 12,
                                      spreadRadius: 0,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Text(
                                  'Continue Training',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF2E2E2E),
                                  ),
                                ),
                              ),
                            ),
                            SoftPillCard(
                              onTap: warmup != null
                                  ? () => _openExercise(
                                      context, warmup.id, warmup.title)
                                  : null,
                              child: ChecklistRow(
                                title: 'Warmup',
                                subtitle: 'Complete',
                                icon: Icons.fitness_center,
                                accentColor: IllustrationAssets.warmupColor,
                                isCompleted: true,
                              ),
                            ),
                            const SizedBox(height: 10),
                            SoftPillCard(
                              onTap: pitch != null
                                  ? () => _openExercise(
                                      context, pitch.id, pitch.title)
                                  : null,
                              child: ChecklistRow(
                                title: 'Pitch Slides',
                                subtitle: 'In Progress • Level 2',
                                icon: Icons.music_note,
                                accentColor: IllustrationAssets.pitchColor,
                                isCompleted: false,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Level 2',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF7A7A7A),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.chevron_right,
                                      size: 20,
                                      color: Color(0xFFA5A5A5),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SoftPillCard(
                              onTap: lipTrills != null
                                  ? () => _openExercise(
                                      context, lipTrills.id, lipTrills.title)
                                  : null,
                              child: ChecklistRow(
                                title: 'Lip Trills',
                                subtitle: 'Next • Level 2',
                                icon: Icons.speed,
                                accentColor: IllustrationAssets.agilityColor,
                                isCompleted: false,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Level 2',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF7A7A7A),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.chevron_right,
                                      size: 20,
                                      color: Color(0xFFA5A5A5),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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

class _ExerciseCheckmark extends StatelessWidget {
  final bool isCompleted;

  const _ExerciseCheckmark({required this.isCompleted});

  @override
  Widget build(BuildContext context) {
    const size = 24.0;

    if (isCompleted) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFF8FC9A8), // Completion green
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.check,
          size: 16,
          color: Colors.white,
        ),
      );
    } else {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFFD1D1D6),
            width: 2,
          ),
        ),
      );
    }
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
