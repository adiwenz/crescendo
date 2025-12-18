import '../models/category.dart';
import '../models/exercise.dart';
import '../services/exercise_repository.dart';
import '../models/vocal_exercise.dart';

List<Category> seedLibraryCategories() {
  return [
    _cat('warmup', 'Warmup', 'Ease in with gentle starters', 0),
    _cat('program', 'Program', 'Core exercises from your plan', 1),
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

final _repo = ExerciseRepository();
final _all = _repo.getExercises();

List<Exercise> seedExercisesFor(String categoryId) {
  List<Exercise> pick(String seedCategoryId, int limit) {
    final list = _all.where((e) => e.categoryId == seedCategoryId).toList();
    return list.take(limit).map<Exercise>(_toExercise).toList();
  }

  switch (categoryId) {
    case 'warmup':
      return pick('recovery_therapy', 6);
    case 'pitch':
      return pick('intonation', 6);
    case 'agility':
      return pick('agility_runs', 6);
    case 'stability':
      return pick('range_building', 6);
    case 'program':
    default:
      final remaining = _all.where((e) => e.categoryId != 'recovery_therapy').take(8).toList();
      return remaining.map<Exercise>(_toExercise).toList();
  }
}

Exercise _toExercise(VocalExercise ex) {
  return Exercise(
    id: ex.id,
    categoryId: ex.categoryId,
    title: ex.name,
    subtitle: ex.description,
    bannerStyleId: ex.categoryId.hashCode % 5,
  );
}
