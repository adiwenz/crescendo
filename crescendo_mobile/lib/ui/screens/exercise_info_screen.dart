import 'package:flutter/material.dart';

import '../../data/progress_repository.dart';
import '../../models/last_take.dart';
import '../../models/pitch_highway_difficulty.dart';
import '../../models/reference_note.dart';
import '../../models/vocal_exercise.dart';
import '../../models/exercise_instance.dart';
import '../../models/pitch_highway_spec.dart';
import '../../models/pitch_segment.dart';
import '../../services/exercise_repository.dart';
import '../../services/last_take_store.dart';
import '../../services/audio_synth_service.dart';
import '../../services/unlock_service.dart';
import '../../services/range_exercise_generator.dart';
import '../../services/range_store.dart';
import '../../utils/pitch_highway_tempo.dart';
import '../widgets/exercise_icon.dart';
import 'exercise_player_screen.dart';
import 'exercise_navigation.dart';
import 'pitch_highway_review_screen.dart';

class ExerciseInfoScreen extends StatefulWidget {
  final String exerciseId;

  const ExerciseInfoScreen({super.key, required this.exerciseId});

  @override
  State<ExerciseInfoScreen> createState() => _ExerciseInfoScreenState();
}

class _ExerciseInfoScreenState extends State<ExerciseInfoScreen> {
  final _repo = ExerciseRepository();
  final _progress = ProgressRepository();
  final _lastTakeStore = LastTakeStore();
  final AudioSynthService _synth = AudioSynthService();
  final UnlockService _unlockService = UnlockService();
  final _rangeStore = RangeStore();
  final _rangeGenerator = RangeExerciseGenerator();
  PitchHighwayDifficulty _tempoDifficulty = PitchHighwayDifficulty.medium;
  int _maxUnlocked = 0;
  bool _unlockLoaded = false;
  double? _lastScore;
  LastTake? _lastTake;
  bool _lastTakeLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadLastScore();
    _loadLastTake();
    _loadUnlock();
  }

  @override
  void dispose() {
    _synth.dispose();
    super.dispose();
  }

  Future<void> _loadLastScore() async {
    final attempts = await _progress.fetchAttemptsForExercise(widget.exerciseId);
    if (!mounted) return;
    if (attempts.isEmpty) {
      setState(() => _lastScore = null);
      return;
    }
    attempts.sort((a, b) => b.completedAt.compareTo(a.completedAt));
    setState(() => _lastScore = attempts.first.overallScore);
  }

  Future<void> _loadLastTake() async {
    final take = await _lastTakeStore.getLastTake(widget.exerciseId);
    if (!mounted) return;
    setState(() {
      _lastTake = take;
      _lastTakeLoaded = true;
    });
  }

  Future<void> _loadUnlock() async {
    final maxUnlocked = await _unlockService.getMaxUnlocked(widget.exerciseId);
    if (!mounted) return;
    setState(() {
      _maxUnlocked = maxUnlocked;
      _unlockLoaded = true;
      final currentIdx = pitchHighwayDifficultyIndex(_tempoDifficulty);
      if (currentIdx > _maxUnlocked) {
        _tempoDifficulty = pitchHighwayDifficultyFromIndex(_maxUnlocked);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final exercise = _repo.getExercise(widget.exerciseId);
    final durationSeconds = exercise.durationSeconds;
    final timeChip = durationSeconds != null
        ? (durationSeconds < 60
            ? '${durationSeconds}s'
            : '${exercise.estimatedMinutes} min')
        : (exercise.reps != null ? '${exercise.reps} reps' : '—');
    final typeLabel = _typeLabel(exercise.type);
    final isPitchHighway = exercise.type == ExerciseType.pitchHighway;
    final canPreviewAudio = isPitchHighway &&
        exercise.highwaySpec?.segments.isNotEmpty == true;
    final canReview = isPitchHighway && _lastTake != null;
    final selectedIdx = pitchHighwayDifficultyIndex(_tempoDifficulty);
    final selectionLocked = isPitchHighway && selectedIdx > _maxUnlocked;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(exercise.name),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              ExerciseIcon(iconKey: exercise.iconKey, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Text(exercise.name,
                    style: Theme.of(context).textTheme.headlineSmall),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(label: typeLabel),
              _InfoChip(label: _difficultyLabel(exercise.difficulty)),
              _InfoChip(label: timeChip),
            ],
          ),
          if (isPitchHighway) ...[
            const SizedBox(height: 16),
            _SectionHeader(title: 'Tempo Difficulty'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: PitchHighwayDifficulty.values.map((difficulty) {
                final selected = _tempoDifficulty == difficulty;
                final idx = pitchHighwayDifficultyIndex(difficulty);
                final unlocked = idx <= _maxUnlocked;
                return ChoiceChip(
                  label: Text(pitchHighwayDifficultyLabel(difficulty)),
                  selected: selected,
                  labelStyle: unlocked
                      ? null
                      : Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(color: Colors.grey[500]),
                  onSelected: (_) {
                    if (!unlocked) {
                      _showLockedHint(idx);
                      return;
                    }
                    setState(() => _tempoDifficulty = difficulty);
                  },
                );
              }).toList(),
            ),
            if (_unlockLoaded && selectionLocked)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _lockedHint(pitchHighwayDifficultyIndex(_tempoDifficulty)),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
          const SizedBox(height: 16),
          _SectionHeader(title: 'How to do it'),
          Text(exercise.description),
          const SizedBox(height: 12),
          _SectionHeader(title: 'Purpose'),
          Text(exercise.purpose),
          const SizedBox(height: 12),
          _SectionHeader(title: 'Targets'),
          ..._targetsForExercise(exercise)
              .map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('- $t'),
                  ))
              .toList(),
          const SizedBox(height: 12),
          _SectionHeader(title: 'Tags'),
          Wrap(
            spacing: 8,
            children: exercise.tags.map((t) => Chip(label: Text(t))).toList(),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: canPreviewAudio ? () => _playPreview(exercise) : null,
            icon: const Icon(Icons.volume_up),
            label: const Text('Preview Exercise'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: selectionLocked
                ? null
                : () async {
                    await _synth.stop();
                    await _startExercise(exercise);
                    await _loadLastScore();
                    await _loadLastTake();
                    await _loadUnlock();
                  },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Exercise'),
          ),
          if (exercise.type == ExerciseType.pitchHighway) ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: canReview
                  ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PitchHighwayReviewScreen(
                            exercise: exercise,
                            lastTake: _lastTake!,
                          ),
                        ),
                      );
                    }
                  : null,
              icon: const Icon(Icons.replay),
              label: const Text('Review last take'),
            ),
            if (_lastTakeLoaded && !canReview)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'No last take recorded yet.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back'),
          ),
          const SizedBox(height: 16),
          Text(
            'Last score: ${_lastScore?.toStringAsFixed(0) ?? '—'}%',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Future<void> _startExercise(VocalExercise exercise) async {
    if (exercise.type == ExerciseType.pitchHighway) {
      final range = await _rangeStore.getRange();
      final lowest = range.$1;
      final highest = range.$2;
      if (lowest != null && highest != null) {
        final instances = _rangeGenerator.generate(
          exercise: exercise,
          lowestMidi: lowest,
          highestMidi: highest,
        );
        if (instances.isNotEmpty) {
          final combined = _buildConcatenatedExercise(exercise, instances);
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ExercisePlayerScreen(
                exercise: combined,
                pitchDifficulty: _tempoDifficulty,
              ),
            ),
          );
          return;
        }
      }
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => buildExerciseScreen(
          exercise,
          pitchDifficulty: _tempoDifficulty,
        ),
      ),
    );
  }

  VocalExercise _buildConcatenatedExercise(
    VocalExercise base,
    List<ExerciseInstance> instances,
  ) {
    final baseSpec = base.highwaySpec;
    if (baseSpec == null || baseSpec.segments.isEmpty) return base;
    final stitched = <PitchSegment>[];
    var cursorMs = 0;
    const gapMs = 1000;
    for (final instance in instances) {
      final applied = instance.apply(base);
      final spec = applied.highwaySpec;
      if (spec == null || spec.segments.isEmpty) continue;
      var localEnd = 0;
      for (final seg in spec.segments) {
        stitched.add(PitchSegment(
          startMs: seg.startMs + cursorMs,
          endMs: seg.endMs + cursorMs,
          midiNote: seg.midiNote,
          toleranceCents: seg.toleranceCents,
          label: seg.label,
          startMidi: seg.startMidi,
          endMidi: seg.endMidi,
        ));
        if (seg.endMs > localEnd) localEnd = seg.endMs;
      }
      cursorMs += localEnd + gapMs;
    }
    final durationSec = (cursorMs / 1000.0).round();
    return VocalExercise(
      id: base.id,
      name: base.name,
      categoryId: base.categoryId,
      type: base.type,
      description: base.description,
      purpose: base.purpose,
      difficulty: base.difficulty,
      tags: base.tags,
      createdAt: base.createdAt,
      iconKey: base.iconKey,
      estimatedMinutes: base.estimatedMinutes,
      durationSeconds: durationSec,
      reps: base.reps,
      highwaySpec: PitchHighwaySpec(segments: stitched),
    );
  }

  void _showLockedHint(int difficultyIdx) {
    final nextLabel = pitchHighwayDifficultyLabel(
      pitchHighwayDifficultyFromIndex(difficultyIdx),
    );
    final requiredLabel = pitchHighwayDifficultyLabel(
      pitchHighwayDifficultyFromIndex((difficultyIdx - 1).clamp(0, 2)),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Score 90% on $requiredLabel to unlock $nextLabel.')),
    );
  }

  String _lockedHint(int difficultyIdx) {
    final nextLabel = pitchHighwayDifficultyLabel(
      pitchHighwayDifficultyFromIndex(difficultyIdx),
    );
    final requiredLabel = pitchHighwayDifficultyLabel(
      pitchHighwayDifficultyFromIndex((difficultyIdx - 1).clamp(0, 2)),
    );
    return 'Score 90% on $requiredLabel to unlock $nextLabel.';
  }

  List<String> _targetsForExercise(VocalExercise exercise) {
    if (exercise.type == ExerciseType.pitchHighway &&
        exercise.highwaySpec?.segments.isNotEmpty == true) {
      final tol = exercise.highwaySpec!.segments.first.toleranceCents.round();
      return ['Pitch accuracy ±$tol cents', 'Stay centered on each note'];
    }
    if (exercise.type == ExerciseType.sustainedPitchHold) {
      return ['Hold within ±25 cents', 'Maintain stability for 3 seconds'];
    }
    if (exercise.type == ExerciseType.dynamicsRamp) {
      return ['Match the loudness ramp', 'Keep tone stable'];
    }
    if (exercise.type == ExerciseType.pitchMatchListening) {
      return ['Match the reference pitch', 'Listen then sing'];
    }
    if (exercise.type == ExerciseType.breathTimer ||
        exercise.type == ExerciseType.sovtTimer ||
        exercise.type == ExerciseType.cooldownRecovery) {
      return ['Complete the full timer cycle', 'Maintain steady airflow'];
    }
    return ['Follow the on-screen guidance'];
  }

  String _difficultyLabel(ExerciseDifficulty difficulty) {
    return switch (difficulty) {
      ExerciseDifficulty.beginner => 'Beginner',
      ExerciseDifficulty.intermediate => 'Intermediate',
      ExerciseDifficulty.advanced => 'Advanced',
    };
  }

  String _typeLabel(ExerciseType type) {
    return switch (type) {
      ExerciseType.pitchHighway => 'Pitch Highway',
      ExerciseType.breathTimer => 'Breath Timer',
      ExerciseType.sovtTimer => 'SOVT Timer',
      ExerciseType.sustainedPitchHold => 'Sustained Hold',
      ExerciseType.pitchMatchListening => 'Pitch Match',
      ExerciseType.articulationRhythm => 'Articulation Rhythm',
      ExerciseType.dynamicsRamp => 'Dynamics Ramp',
      ExerciseType.cooldownRecovery => 'Recovery',
    };
  }

  Future<void> _playPreview(VocalExercise exercise) async {
    final notes = _buildReferenceNotes(exercise, _tempoDifficulty);
    if (notes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No preview available for this exercise.')),
      );
      return;
    }
    await _synth.stop();
    final path = await _synth.renderReferenceNotes(notes);
    await _synth.playFile(path);
  }

  List<ReferenceNote> _buildReferenceNotes(
    VocalExercise exercise,
    PitchHighwayDifficulty difficulty,
  ) {
    final spec = exercise.highwaySpec;
    if (spec == null) return const [];
    final multiplier = PitchHighwayTempo.multiplierFor(difficulty, spec.segments);
    final segments = PitchHighwayTempo.scaleSegments(spec.segments, multiplier);
    final notes = <ReferenceNote>[];
    for (final seg in segments) {
      if (seg.isGlide) {
        final startMidi = seg.startMidi ?? seg.midiNote;
        final endMidi = seg.endMidi ?? seg.midiNote;
        final durationMs = seg.endMs - seg.startMs;
        final steps = (durationMs / 200).round().clamp(4, 24);
        for (var i = 0; i < steps; i++) {
          final ratio = i / steps;
          final midi = (startMidi + (endMidi - startMidi) * ratio).round();
          final stepStart = seg.startMs + (durationMs * ratio).round();
          final stepEnd = seg.startMs + (durationMs * ((i + 1) / steps)).round();
          notes.add(ReferenceNote(
            startSec: stepStart / 1000.0,
            endSec: stepEnd / 1000.0,
            midi: midi,
            lyric: seg.label,
          ));
        }
      } else {
        notes.add(ReferenceNote(
          startSec: seg.startMs / 1000.0,
          endSec: seg.endMs / 1000.0,
          midi: seg.midiNote,
          lyric: seg.label,
        ));
      }
    }
    return notes;
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold));
  }
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
