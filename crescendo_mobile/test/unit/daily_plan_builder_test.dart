import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_mobile/models/daily_plan.dart';
import 'package:crescendo_mobile/services/daily_plan_builder.dart';

void main() {
  group('buildDailyPlan', () {
    test('returns exactly 4 slots', () {
      final plan = buildDailyPlan(
        date: DateTime(2025, 6, 15),
        history: const [],
      );
      expect(plan.slots.length, 4);
    });

    test('slot 1 is always Warmup', () {
      final plan = buildDailyPlan(
        date: DateTime(2025, 6, 15),
        history: const [],
      );
      expect(plan.slots[0].role, DailyPlanRole.warmup);
      expect(plan.slots[0].roleLabel, 'Warmup');
    });

    test('slot 2 is Technique, slot 3 Main Work, slot 4 Finisher', () {
      final plan = buildDailyPlan(
        date: DateTime(2025, 6, 15),
        history: const [],
      );
      expect(plan.slots[1].role, DailyPlanRole.technique);
      expect(plan.slots[2].role, DailyPlanRole.mainWork);
      expect(plan.slots[3].role, DailyPlanRole.finisher);
    });

    test('Warmup slot category is from WarmupRole', () {
      final plan = buildDailyPlan(
        date: DateTime(2025, 6, 15),
        history: const [],
      );
      expect(DailyPlanRoles.warmupRole, contains(plan.slots[0].categoryId));
    });

    test('Technique slot category is from TechniqueRole', () {
      final plan = buildDailyPlan(
        date: DateTime(2025, 6, 15),
        history: const [],
      );
      expect(DailyPlanRoles.techniqueRole, contains(plan.slots[1].categoryId));
    });

    test('Main Work slot category is from MainWorkRole', () {
      final plan = buildDailyPlan(
        date: DateTime(2025, 6, 15),
        history: const [],
      );
      expect(DailyPlanRoles.mainWorkRole, contains(plan.slots[2].categoryId));
    });

    test('Finisher slot category is from CooldownRole', () {
      final plan = buildDailyPlan(
        date: DateTime(2025, 6, 15),
        history: const [],
      );
      expect(DailyPlanRoles.cooldownRole, contains(plan.slots[3].categoryId));
    });

    test('Main Work category never appears twice in same day', () {
      for (var i = 0; i < 20; i++) {
        final plan = buildDailyPlan(
          date: DateTime(2025, 6, 15 + i),
          history: const [],
        );
        final mainWorkCategories = plan.slots
            .where((s) => s.role == DailyPlanRole.mainWork)
            .map((s) => s.categoryId)
            .toList();
        expect(mainWorkCategories.length, 1);
      }
    });

    test('deterministic output for same date and same inputs', () {
      final plan1 = buildDailyPlan(
        date: DateTime(2025, 6, 15),
        history: const [],
      );
      final plan2 = buildDailyPlan(
        date: DateTime(2025, 6, 15),
        history: const [],
      );
      expect(plan1.categoryIds, plan2.categoryIds);
      for (var i = 0; i < plan1.slots.length; i++) {
        expect(plan1.slots[i].categoryId, plan2.slots[i].categoryId);
        expect(plan1.slots[i].reason, plan2.slots[i].reason);
      }
    });

    test('different date can produce different plan', () {
      final plan1 = buildDailyPlan(
        date: DateTime(2025, 6, 15),
        history: const [],
      );
      final plan2 = buildDailyPlan(
        date: DateTime(2025, 6, 16),
        history: const [],
      );
      // At least one slot may differ (not guaranteed for all seeds, but likely)
      final same = plan1.slots.asMap().entries.every(
            (e) => plan2.slots[e.key].categoryId == e.value.categoryId,
          );
      expect(same, isFalse);
    });

    test('pinnedWarmupCategoryId is used for slot 1 when in WarmupRole', () {
      final plan = buildDailyPlan(
        date: DateTime(2025, 6, 15),
        history: const [],
        pinnedWarmupCategoryId: 'breathing_support',
      );
      expect(plan.slots[0].categoryId, 'breathing_support');
      expect(plan.slots[0].reason, 'pinned_warmup');
    });

    test('pinnedWarmupCategoryId sovt is used for slot 1', () {
      final plan = buildDailyPlan(
        date: DateTime(2025, 6, 15),
        history: const [],
        pinnedWarmupCategoryId: 'sovt',
      );
      expect(plan.slots[0].categoryId, 'sovt');
    });

    test('categoryIds returns ordered list of 4 categoryIds', () {
      final plan = buildDailyPlan(
        date: DateTime(2025, 6, 15),
        history: const [],
      );
      expect(plan.categoryIds.length, 4);
      for (var i = 0; i < 4; i++) {
        expect(plan.categoryIds[i], plan.slots[i].categoryId);
      }
    });

    test('each slot has a non-empty reason', () {
      final plan = buildDailyPlan(
        date: DateTime(2025, 6, 15),
        history: const [],
      );
      for (final slot in plan.slots) {
        expect(slot.reason.isNotEmpty, true);
      }
    });

    test('high fatigue: Main Work avoids agility_runs and range_building when possible', () {
      final plan = buildDailyPlan(
        date: DateTime(2025, 6, 15),
        history: const [],
        fatigue: FatigueLevel.high,
      );
      final mainWorkCategory = plan.slots[2].categoryId;
      expect(
        ['register_balance', 'intonation'].contains(mainWorkCategory),
        true,
        reason: 'High fatigue should favor register_balance or intonation',
      );
    });

    test('no duplicate categories by default except Finisher may repeat sovt/resonance', () {
      final plan = buildDailyPlan(
        date: DateTime(2025, 7, 1),
        history: const [],
      );
      final categories = plan.slots.map((s) => s.categoryId).toList();
      final warmup = categories[0];
      final technique = categories[1];
      final mainWork = categories[2];
      final finisher = categories[3];
      expect(technique, isNot(mainWork));
      expect(mainWork, isNot(finisher));
      expect(warmup, isNot(technique));
      // Finisher may equal warmup if both are sovt (Exception A)
      // Finisher may equal technique if both are resonance_placement (Exception A)
    });

    test('anti-repetition: with yesterday warmup in history, today warmup can differ when 2 warmup roles', () {
      final yesterdayKey = '2025-06-14';
      final history = [
        CompletedSession(dateKey: yesterdayKey, categoryId: 'breathing_support'),
      ];
      final plan = buildDailyPlan(
        date: DateTime(2025, 6, 15),
        history: history,
      );
      // Today's warmup may be 'sovt' to avoid repeating 'breathing_support' (when 2 warmup options)
      expect(plan.slots[0].role, DailyPlanRole.warmup);
      expect(DailyPlanRoles.warmupRole, contains(plan.slots[0].categoryId));
    });

    test('DailyPlan.slotAt returns correct slot or null', () {
      final plan = buildDailyPlan(
        date: DateTime(2025, 6, 15),
        history: const [],
      );
      expect(plan.slotAt(0)?.role, DailyPlanRole.warmup);
      expect(plan.slotAt(3)?.role, DailyPlanRole.finisher);
      expect(plan.slotAt(-1), isNull);
      expect(plan.slotAt(4), isNull);
    });
  });
}
