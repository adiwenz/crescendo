import 'dart:math' as math;

import '../models/exercise_note.dart';
import '../models/exercise_note_result.dart';
import '../models/exercise_plan.dart';
import '../models/exercise_run_result.dart';
import '../models/pitch_frame.dart';

class ExerciseRunScoringService {
  ExerciseRunResult score({
    required ExercisePlan plan,
    required List<PitchFrame> frames,
    required DateTime startedAt,
    int offsetMs = 0,
  }) {
    final noteResults = <ExerciseNoteResult>[];
    final offsetSec = offsetMs / 1000.0;
    final avgAbsList = <double>[];

    double cursor = 0;
    for (var i = 0; i < plan.notes.length; i++) {
      final n = plan.notes[i];
      final start = cursor;
      final end = cursor + n.durationSec;
      cursor = end + plan.gapSec;

      final noteFrames = frames.where((f) {
        final t = f.time - offsetSec;
        return t >= start && t <= end && f.midi != null;
      }).toList();

      final centsSamples = noteFrames
          .map((f) => (f.midi! - n.midi) * 100)
          .toList();

      if (centsSamples.isEmpty) {
        noteResults.add(ExerciseNoteResult(
          noteIndex: i,
          targetMidi: n.midi,
          pctOnPitch: 0,
          avgCents: 0,
          avgAbsCents: 100,
          medianAbsCents: 100,
          maxAbsCents: 100,
        ));
        avgAbsList.add(100);
        continue;
      }

      final avg = centsSamples.reduce((a, b) => a + b) / centsSamples.length;
      final abs = centsSamples.map((c) => c.abs()).toList();
      final avgAbs = abs.reduce((a, b) => a + b) / abs.length;
      final sorted = List<double>.from(abs)..sort();
      final median = sorted[sorted.length ~/ 2];
      final maxAbs = abs.reduce(math.max);

      final pctOn = abs.where((c) => c <= 25).length / abs.length;
      noteResults.add(ExerciseNoteResult(
        noteIndex: i,
        targetMidi: n.midi,
        pctOnPitch: pctOn,
        avgCents: avg,
        avgAbsCents: avgAbs,
        medianAbsCents: median,
        maxAbsCents: maxAbs,
      ));
      avgAbsList.add(avgAbs);
    }

    final perNoteScores = noteResults.map((nr) {
      final base = (100 - nr.avgAbsCents * 1.2).clamp(0, 100);
      final sustained = 0.5 + 0.5 * nr.pctOnPitch;
      return base * sustained;
    }).toList();
    final overall = perNoteScores.isNotEmpty
        ? perNoteScores.reduce((a, b) => a + b) / perNoteScores.length
        : 0.0;
    final stars = _starsForScore(overall);
    final avgAbsAll = avgAbsList.isNotEmpty
        ? avgAbsList.reduce((a, b) => a + b) / avgAbsList.length
        : 0.0;

    return ExerciseRunResult(
      exerciseId: plan.id,
      startedAt: startedAt,
      offsetMsUsed: offsetMs,
      overallScore0to100: overall,
      stars: stars,
      noteResults: noteResults,
      avgAbsCents: avgAbsAll,
    );
  }

  int _starsForScore(double s) {
    if (s >= 90) return 5;
    if (s >= 75) return 4;
    if (s >= 60) return 3;
    if (s >= 40) return 2;
    return 1;
  }
}
