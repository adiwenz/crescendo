import 'dart:math';

import '../models/daily_plan.dart';

/// Role category definitions for the daily plan.
class DailyPlanRoles {
  static const List<String> warmupRole = ['breathing_support', 'sovt'];
  static const List<String> techniqueRole = ['onset_release', 'resonance_placement'];
  static const List<String> mainWorkRole = [
    'register_balance',
    'range_building',
    'agility_runs',
    'intonation',
  ];
  static const List<String> cooldownRole = ['sovt', 'resonance_placement', 'intonation'];

  static bool isWarmup(String categoryId) => warmupRole.contains(categoryId);
  static bool isTechnique(String categoryId) => techniqueRole.contains(categoryId);
  static bool isMainWork(String categoryId) => mainWorkRole.contains(categoryId);
  static bool isCooldown(String categoryId) => cooldownRole.contains(categoryId);
}

/// Builds a deterministic daily plan for the given date and inputs.
///
/// - [date] Used for seed (yyyy-mm-dd) so the plan is stable for that day.
/// - [history] Completed sessions (e.g. last 7+ days) for anti-repetition and weekly balance.
/// - [goal] Optional user goal (range, runs, pitch).
/// - [fatigue] When high, Main Work favors register_balance/intonation; Finisher favors sovt/resonance.
/// - [pinnedWarmupCategoryId] If set and in WarmupRole, always use for slot 1.
///
/// Returns a [DailyPlan] with exactly 4 slots: Warmup, Technique, Main Work, Finisher.
DailyPlan buildDailyPlan({
  required DateTime date,
  required List<CompletedSession> history,
  UserGoal? goal,
  FatigueLevel fatigue = FatigueLevel.medium,
  String? pinnedWarmupCategoryId,
}) {
  final dateKey = _dateKey(date);
  final seed = dateKey.hashCode;
  final random = Random(seed);

  final slots = <DailyPlanSlot>[];

  // Yesterday's categories for anti-repetition (warmup and main work)
  final yesterdayKey = _dateKey(date.subtract(const Duration(days: 1)));
  final yesterdaySessions = history.where((s) => s.dateKey == yesterdayKey).toList();
  final yesterdayCategoryIds = yesterdaySessions.map((s) => s.categoryId).toSet();
  final yesterdayWarmupCats = yesterdayCategoryIds.where((c) => DailyPlanRoles.isWarmup(c)).toList();
  final yesterdayMainWorkCats = yesterdayCategoryIds.where((c) => DailyPlanRoles.isMainWork(c)).toList();
  final yesterdayWarmup = yesterdayWarmupCats.isEmpty ? null : yesterdayWarmupCats.first;
  final yesterdayMainWork = yesterdayMainWorkCats.isEmpty ? null : yesterdayMainWorkCats.first;

  // Last 7 days Main Work category counts (for weekly balance: prefer 3+ distinct)
  final last7Keys = List.generate(7, (i) => _dateKey(date.subtract(Duration(days: i))));
  final mainWorkInLast7 = <String>{};
  for (final s in history) {
    if (last7Keys.contains(s.dateKey) && DailyPlanRoles.isMainWork(s.categoryId)) {
      mainWorkInLast7.add(s.categoryId);
    }
  }
  final mainWorkCountByCategory = <String, int>{};
  for (final d in last7Keys) {
    for (final s in history) {
      if (s.dateKey == d && DailyPlanRoles.isMainWork(s.categoryId)) {
        mainWorkCountByCategory[s.categoryId] = (mainWorkCountByCategory[s.categoryId] ?? 0) + 1;
      }
    }
  }

  final usedCategoriesToday = <String>{};

  // --- Slot 1: Warmup (exactly one; always first) ---
  final warmupCategory = _pickWarmup(
    random: random,
    pinnedWarmupCategoryId: pinnedWarmupCategoryId,
    yesterdayWarmup: yesterdayWarmup,
  );
  slots.add(DailyPlanSlot(
    role: DailyPlanRole.warmup,
    categoryId: warmupCategory,
    reason: pinnedWarmupCategoryId != null && DailyPlanRoles.isWarmup(pinnedWarmupCategoryId)
        ? 'pinned_warmup'
        : 'seed_rotation',
  ));
  usedCategoriesToday.add(warmupCategory);

  // --- Slot 2: Technique (1 category; no repeat) ---
  final techniqueCandidates = List<String>.from(DailyPlanRoles.techniqueRole)
    ..removeWhere(usedCategoriesToday.contains);
  if (techniqueCandidates.isEmpty) {
    techniqueCandidates.addAll(DailyPlanRoles.techniqueRole);
    techniqueCandidates.removeWhere(usedCategoriesToday.contains);
  }
  if (techniqueCandidates.isEmpty) techniqueCandidates.addAll(DailyPlanRoles.techniqueRole);
  final techniqueCategory = techniqueCandidates[random.nextInt(techniqueCandidates.length)];
  slots.add(DailyPlanSlot(
    role: DailyPlanRole.technique,
    categoryId: techniqueCategory,
    reason: 'technique_slot',
  ));
  usedCategoriesToday.add(techniqueCategory);

  // --- Slot 3: Main Work (1 category; never repeat in day; avoid yesterday; weekly balance; fatigue) ---
  List<String> mainWorkCandidates = List<String>.from(DailyPlanRoles.mainWorkRole)
    ..removeWhere(usedCategoriesToday.contains);

  if (fatigue == FatigueLevel.high) {
    mainWorkCandidates.removeWhere((c) => c == 'agility_runs' || c == 'range_building');
    if (mainWorkCandidates.isEmpty) mainWorkCandidates.addAll(['register_balance', 'intonation']);
  }
  if (yesterdayMainWork != null && mainWorkCandidates.length > 1) {
    mainWorkCandidates.remove(yesterdayMainWork);
    if (mainWorkCandidates.isEmpty) mainWorkCandidates.addAll(DailyPlanRoles.mainWorkRole);
  }
  // Weekly balance: prefer category used least in last 7 days
  if (mainWorkCandidates.length > 1) {
    final minCount = mainWorkCandidates
        .map((c) => mainWorkCountByCategory[c] ?? 0)
        .reduce((a, b) => a < b ? a : b);
    final leastUsed = mainWorkCandidates
        .where((c) => (mainWorkCountByCategory[c] ?? 0) == minCount)
        .toList();
    if (leastUsed.isNotEmpty) {
      mainWorkCandidates.clear();
      mainWorkCandidates.addAll(leastUsed);
    }
  }
  final mainWorkCategory = mainWorkCandidates[random.nextInt(mainWorkCandidates.length)];
  slots.add(DailyPlanSlot(
    role: DailyPlanRole.mainWork,
    categoryId: mainWorkCategory,
    reason: fatigue == FatigueLevel.high ? 'main_work_fatigue_downshift' : 'main_work_slot',
  ));
  usedCategoriesToday.add(mainWorkCategory);

  // --- Slot 4: Finisher/Cooldown (1 category; Exception A: may repeat sovt/resonance as cooldown) ---
  List<String> cooldownCandidates = List<String>.from(DailyPlanRoles.cooldownRole);
  // By default do not repeat categories; Exception A: Finisher may repeat warmup-adjacent (sovt, resonance) as cooldown
  final canRepeatForCooldown = ['sovt', 'resonance_placement'];
  cooldownCandidates.removeWhere((c) {
    if (usedCategoriesToday.contains(c)) {
      return !canRepeatForCooldown.contains(c); // allow repeat only for sovt/resonance
    }
    return false;
  });
  if (cooldownCandidates.isEmpty) cooldownCandidates.addAll(DailyPlanRoles.cooldownRole);
  if (fatigue == FatigueLevel.high) {
    cooldownCandidates.retainWhere((c) => c == 'sovt' || c == 'resonance_placement');
    if (cooldownCandidates.isEmpty) cooldownCandidates.addAll(['sovt', 'resonance_placement']);
  }
  final finisherCategory = cooldownCandidates[random.nextInt(cooldownCandidates.length)];
  slots.add(DailyPlanSlot(
    role: DailyPlanRole.finisher,
    categoryId: finisherCategory,
    reason: fatigue == FatigueLevel.high ? 'finisher_fatigue_sovt_resonance' : 'finisher_slot',
  ));

  return DailyPlan(date: date, slots: slots);
}

String _dateKey(DateTime d) {
  final y = d.year;
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

String _pickWarmup({
  required Random random,
  String? pinnedWarmupCategoryId,
  String? yesterdayWarmup,
}) {
  if (pinnedWarmupCategoryId != null && DailyPlanRoles.isWarmup(pinnedWarmupCategoryId)) {
    return pinnedWarmupCategoryId;
  }
  final candidates = List<String>.from(DailyPlanRoles.warmupRole);
  if (yesterdayWarmup != null && candidates.length > 1) {
    candidates.remove(yesterdayWarmup);
    if (candidates.isEmpty) candidates.add(DailyPlanRoles.warmupRole.first);
  }
  return candidates[random.nextInt(candidates.length)];
}
