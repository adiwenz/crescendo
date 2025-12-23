import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/seed_library.dart';
import '../../widgets/home/checklist_row.dart';
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
                            // Today's Exercises section (moved to top)
                            const Padding(
                              padding:
                                  EdgeInsets.only(left: 4, bottom: 8, top: 24),
                              child: Text(
                                'Today\'s Exercises',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF2E2E2E),
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
                                subtitle: 'Level 1',
                                icon: Icons.fitness_center,
                                accentColor: IllustrationAssets.warmupColor,
                                isCompleted: true, // Marked as completed
                              ),
                            ),
                            const SizedBox(height: 10),
                            SoftPillCard(
                              onTap: pitch != null
                                  ? () => _openExercise(
                                      context, pitch.id, pitch.title)
                                  : null,
                              child: ChecklistRow(
                                title: 'Build pitch accuracy',
                                subtitle: 'Level 1',
                                icon: Icons.music_note,
                                accentColor: IllustrationAssets.pitchColor,
                                isCompleted: false,
                                trailing: const Icon(
                                  Icons.chevron_right,
                                  size: 20,
                                  color: Color(0xFFA5A5A5),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            // Continue Training section
                            const Padding(
                              padding: EdgeInsets.only(left: 4, bottom: 8),
                              child: Text(
                                'Continue Training',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF2E2E2E),
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

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
