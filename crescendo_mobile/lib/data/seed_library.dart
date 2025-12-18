import '../models/category.dart';
import '../models/exercise.dart';

List<Category> seedLibraryCategories() {
  return [
    _cat('warmup', 'Warmup', 'Ease in with gentle starters', 0),
    _cat('program', 'Exercise from your program', 'Coach-picked drills', 1),
    _cat('pitch', 'Pitch Accuracy', 'Dial in your center', 2),
    _cat('agility', 'Agility', 'Move quickly and cleanly', 3),
    _cat('stability', 'Stability & Holds', 'Sustain with control', 4),
  ];
}

Category _cat(String id, String title, String subtitle, int banner) {
  return Category(
    id: id,
    title: title,
    subtitle: subtitle,
    bannerStyleId: banner,
  );
}

List<Exercise> seedExercisesFor(String categoryId) {
  final patterns = [
    'Scale',
    'Glide',
    'Arpeggio',
    'Interval',
    'Sustain',
    'Pattern',
  ];
  final count = 4 + (categoryId.hashCode % 4); // 4–7 items
  return List.generate(count, (i) {
    final label = patterns[i % patterns.length];
    return Exercise(
      id: '$categoryId-ex-$i',
      categoryId: categoryId,
      title: '$label ${i + 1}',
      subtitle: 'Short focused drill ${i + 1}',
      bannerStyleId: (i + categoryId.length) % 5,
    );
  });
}
