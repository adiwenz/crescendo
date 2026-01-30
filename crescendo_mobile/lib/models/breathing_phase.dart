/// Animation type for breathing phases
enum BreathingAnimationType {
  expand,   // Scale up (inhale)
  contract, // Scale down (exhale)
  hold,     // Stay at current size
  pulse,    // Subtle pulsing (optional)
}

/// Defines a single phase in a breathing exercise
class BreathingPhase {
  final String name;
  final double durationSeconds;
  final BreathingAnimationType animationType;
  final bool enableHaptic; // Optional haptic at phase start

  const BreathingPhase({
    required this.name,
    required this.durationSeconds,
    required this.animationType,
    this.enableHaptic = false,
  });

  /// Total duration in milliseconds
  int get durationMs => (durationSeconds * 1000).round();
}

/// Pre-defined breathing patterns
class BreathingPatterns {
  /// Appoggio breathing: 5s inhale, 5s hold, 5s exhale
  static const List<BreathingPhase> appoggio = [
    BreathingPhase(
      name: 'Inhale',
      durationSeconds: 5.0,
      animationType: BreathingAnimationType.expand,
      enableHaptic: true,
    ),
    BreathingPhase(
      name: 'Hold',
      durationSeconds: 5.0,
      animationType: BreathingAnimationType.hold,
    ),
    BreathingPhase(
      name: 'Exhale',
      durationSeconds: 5.0,
      animationType: BreathingAnimationType.contract,
    ),
  ];

  /// Box breathing: 4s inhale, 4s hold, 4s exhale, 4s hold
  static const List<BreathingPhase> box = [
    BreathingPhase(
      name: 'Inhale',
      durationSeconds: 4.0,
      animationType: BreathingAnimationType.expand,
      enableHaptic: true,
    ),
    BreathingPhase(
      name: 'Hold',
      durationSeconds: 4.0,
      animationType: BreathingAnimationType.hold,
    ),
    BreathingPhase(
      name: 'Exhale',
      durationSeconds: 4.0,
      animationType: BreathingAnimationType.contract,
    ),
    BreathingPhase(
      name: 'Hold',
      durationSeconds: 4.0,
      animationType: BreathingAnimationType.hold,
    ),
  ];

  /// 4-7-8 breathing: 4s inhale, 7s hold, 8s exhale
  static const List<BreathingPhase> fourSevenEight = [
    BreathingPhase(
      name: 'Inhale',
      durationSeconds: 4.0,
      animationType: BreathingAnimationType.expand,
      enableHaptic: true,
    ),
    BreathingPhase(
      name: 'Hold',
      durationSeconds: 7.0,
      animationType: BreathingAnimationType.hold,
    ),
    BreathingPhase(
      name: 'Exhale',
      durationSeconds: 8.0,
      animationType: BreathingAnimationType.contract,
    ),
  ];
}
