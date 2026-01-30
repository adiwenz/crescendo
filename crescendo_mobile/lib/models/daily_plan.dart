/// Role of a slot in the daily plan.
enum DailyPlanRole {
  warmup,
  technique,
  mainWork,
  finisher,
}

/// User goal for personalization (optional).
enum UserGoal {
  range,
  runs,
  pitch,
}

/// Fatigue level for personalization (affects Main Work and Finisher choices).
enum FatigueLevel {
  low,
  medium,
  high,
}

/// A completed session record (from history) for anti-repetition and weekly balance.
class CompletedSession {
  final String dateKey;
  final String categoryId;
  final String? exerciseId;

  const CompletedSession({
    required this.dateKey,
    required this.categoryId,
    this.exerciseId,
  });
}

/// One slot in the daily plan: role, chosen category, and debug reason.
class DailyPlanSlot {
  final DailyPlanRole role;
  final String categoryId;
  final String reason;

  const DailyPlanSlot({
    required this.role,
    required this.categoryId,
    required this.reason,
  });

  String get roleLabel {
    switch (role) {
      case DailyPlanRole.warmup:
        return 'Warmup';
      case DailyPlanRole.technique:
        return 'Technique';
      case DailyPlanRole.mainWork:
        return 'Main Work';
      case DailyPlanRole.finisher:
        return 'Finisher';
    }
  }
}

/// Full daily plan: ordered slots with categoryIds and metadata.
class DailyPlan {
  final DateTime date;
  final List<DailyPlanSlot> slots;

  const DailyPlan({
    required this.date,
    required this.slots,
  });

  /// Ordered list of categoryIds for the day (one per slot).
  List<String> get categoryIds => slots.map((s) => s.categoryId).toList();

  DailyPlanSlot? slotAt(int index) {
    if (index < 0 || index >= slots.length) return null;
    return slots[index];
  }
}
