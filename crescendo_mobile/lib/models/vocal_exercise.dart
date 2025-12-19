import 'exercise_note_segment.dart';
import 'pitch_highway_spec.dart';
import 'pitch_segment.dart';

enum ExerciseType {
  pitchHighway,
  breathTimer,
  sovtTimer,
  sustainedPitchHold,
  pitchMatchListening,
  articulationRhythm,
  dynamicsRamp,
  cooldownRecovery,
}

enum ExerciseDifficulty { beginner, intermediate, advanced }

class VocalExercise {
  final String id;
  final String name;
  final String categoryId;
  final ExerciseType type;
  final String description;
  final String purpose;
  final int? durationSeconds;
  final int? reps;
  final ExerciseDifficulty difficulty;
  final List<String> tags;
  final PitchHighwaySpec? highwaySpec;
  final DateTime createdAt;
  final String iconKey;
  final int estimatedMinutes;

  VocalExercise({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.type,
    required this.description,
    required this.purpose,
    required this.difficulty,
    required this.tags,
    required this.createdAt,
    String? iconKey,
    int? estimatedMinutes,
    this.durationSeconds,
    this.reps,
    this.highwaySpec,
  })  : iconKey = iconKey ?? _defaultIconKey(type),
        estimatedMinutes = estimatedMinutes ?? _estimateMinutes(durationSeconds);

  VocalExercise transpose(int semitones) {
    if (semitones == 0 || highwaySpec == null) return this;
    final segments = highwaySpec!.segments
        .map(
          (s) => PitchSegment(
            startMs: s.startMs,
            endMs: s.endMs,
            midiNote: s.midiNote + semitones,
            toleranceCents: s.toleranceCents,
            label: s.label,
            startMidi: s.startMidi != null ? s.startMidi! + semitones : null,
            endMidi: s.endMidi != null ? s.endMidi! + semitones : null,
          ),
        )
        .toList();
    return VocalExercise(
      id: id,
      name: name,
      categoryId: categoryId,
      type: type,
      description: description,
      purpose: purpose,
      difficulty: difficulty,
      tags: tags,
      createdAt: createdAt,
      iconKey: iconKey,
      estimatedMinutes: estimatedMinutes,
      durationSeconds: durationSeconds,
      reps: reps,
      highwaySpec: PitchHighwaySpec(segments: segments),
    );
  }

  static String _defaultIconKey(ExerciseType type) {
    return switch (type) {
      ExerciseType.pitchHighway => 'pitch',
      ExerciseType.breathTimer => 'breath',
      ExerciseType.sovtTimer => 'sovt',
      ExerciseType.sustainedPitchHold => 'hold',
      ExerciseType.pitchMatchListening => 'listen',
      ExerciseType.articulationRhythm => 'articulation',
      ExerciseType.dynamicsRamp => 'dynamics',
      ExerciseType.cooldownRecovery => 'recovery',
    };
  }

  static int _estimateMinutes(int? durationSeconds) {
    if (durationSeconds == null || durationSeconds <= 0) return 2;
    final mins = (durationSeconds / 60).round();
    return mins.clamp(1, 60);
  }

  List<ExerciseNoteSegment> buildPreviewSegments({int maxSegments = 10}) {
    final spec = highwaySpec;
    if (spec == null || spec.segments.isEmpty) return const [];
    final segments = <ExerciseNoteSegment>[];
    for (final seg in spec.segments) {
      final startSec = seg.startMs / 1000.0;
      final durationSec = (seg.endMs - seg.startMs) / 1000.0;
      if (seg.isGlide) {
        final startMidi = seg.startMidi ?? seg.midiNote;
        final endMidi = seg.endMidi ?? seg.midiNote;
        final steps = (durationSec / 0.2).round().clamp(3, 6);
        final stepDur = durationSec / steps;
        for (var i = 0; i < steps; i++) {
          final ratio = i / (steps - 1);
          final midi = (startMidi + (endMidi - startMidi) * ratio).round();
          segments.add(ExerciseNoteSegment(
            midi: midi,
            startSec: startSec + stepDur * i,
            durationSec: stepDur,
            syllable: seg.label,
          ));
        }
      } else {
        segments.add(ExerciseNoteSegment(
          midi: seg.midiNote,
          startSec: startSec,
          durationSec: durationSec,
          syllable: seg.label,
        ));
      }
    }
    if (segments.length <= maxSegments) return segments;
    final stride = segments.length / maxSegments;
    final sampled = <ExerciseNoteSegment>[];
    for (var i = 0; i < maxSegments; i++) {
      final idx = (i * stride).floor().clamp(0, segments.length - 1);
      sampled.add(segments[idx]);
    }
    return sampled;
  }

  bool get usesPitchHighway => type == ExerciseType.pitchHighway;
}
