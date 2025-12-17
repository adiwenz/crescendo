import 'package:flutter_test/flutter_test.dart';

import 'package:crescendo_mobile/data/exercise_seed.dart';

void main() {
  test('seeded categories and exercises count', () {
    final categories = seedExerciseCategories();
    final exercises = seedVocalExercises();
    expect(categories.length, 13);
    expect(exercises.length, 43);
  });

  test('exercises reference valid categories', () {
    final categories = seedExerciseCategories();
    final exercises = seedVocalExercises();
    final ids = categories.map((c) => c.id).toSet();
    for (final ex in exercises) {
      expect(ids.contains(ex.categoryId), isTrue, reason: ex.id);
    }
  });
}
