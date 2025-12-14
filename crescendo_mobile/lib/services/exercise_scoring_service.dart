import '../models/exercise_note.dart';

class ExerciseNoteScore {
  int on = 0;
  int near = 0;
  int off = 0;

  double get onPct {
    final total = on + near + off;
    if (total == 0) return 0;
    return on / total * 100;
  }

  NoteRating get rating {
    final pct = onPct;
    if (pct >= 70) return NoteRating.good;
    if (pct >= 40) return NoteRating.near;
    return NoteRating.off;
  }
}

enum NoteRating { good, near, off }

class ExerciseScoringService {
  List<ExerciseNoteScore> emptyScores(int len) => List.generate(len, (_) => ExerciseNoteScore());
}
