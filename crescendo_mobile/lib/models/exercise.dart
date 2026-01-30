import 'breathing_phase.dart';

class Exercise {
  final String id;
  final String categoryId;
  final String title;
  final String subtitle;
  final int bannerStyleId;
  final bool isBreathingExercise;
  final List<BreathingPhase>? breathingPhases;
  final int? breathingRepeatCount; // null = 1, 0 = infinite

  const Exercise({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.subtitle,
    required this.bannerStyleId,
    this.isBreathingExercise = false,
    this.breathingPhases,
    this.breathingRepeatCount,
  });
}
