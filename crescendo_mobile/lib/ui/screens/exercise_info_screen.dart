import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../data/progress_repository.dart';
import '../../models/exercise_attempt.dart';
import '../../models/pitch_highway_difficulty.dart';
import '../../models/vocal_exercise.dart';
import '../../models/exercise_level_progress.dart';
import '../../services/exercise_repository.dart';
import '../../services/preview_audio_service.dart';
import '../../services/exercise_metadata.dart';
import '../../services/exercise_level_progress_repository.dart';
import '../../widgets/home/home_category_banner_row.dart';
import '../widgets/exercise_icon.dart';
import 'exercise_player_screen.dart';
import 'exercise_navigation.dart';
import 'exercise_review_summary_screen.dart';
import '../../services/attempt_repository.dart';
import '../../services/reference_audio_generator.dart';
import '../../models/exercise_plan.dart';
import '../../utils/pitch_math.dart';

class ExerciseInfoScreen extends StatefulWidget {
  final String exerciseId;

  const ExerciseInfoScreen({super.key, required this.exerciseId});

  @override
  State<ExerciseInfoScreen> createState() => _ExerciseInfoScreenState();
}

class _ExerciseInfoScreenState extends State<ExerciseInfoScreen> {
  final _repo = ExerciseRepository();
  final _progress = ProgressRepository();
  final _attempts = AttemptRepository.instance;
  final PreviewAudioService _previewAudio = PreviewAudioService();
  final ExerciseLevelProgressRepository _levelProgress =
      ExerciseLevelProgressRepository();
  int _highestUnlockedLevel = ExerciseLevelProgress.minLevel;
  int _selectedLevel = ExerciseLevelProgress.minLevel;
  int? _highlightedLevel;
  Map<int, int> _bestScoresByLevel = const <int, int>{};
  bool _progressLoaded = false;
  double? _lastScore;
  ExerciseAttempt? _latestAttempt;
  bool _preparing = false;
  Future<ExercisePlan>? _planFuture;

  @override
  void initState() {
    super.initState();
    _loadLastScore();
    _loadLatestAttempt();
    _loadProgress();
    
    // Requirements: Defer heavy generation until after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _triggerPreparation();
      }
    });
  }

  @override
  void dispose() {
    _previewAudio.dispose();
    super.dispose();
  }

  Future<void> _loadLastScore() async {
    final attempts = await _progress.fetchAttemptsForExercise(widget.exerciseId);
    if (!mounted) return;
    if (attempts.isEmpty) {
      setState(() => _lastScore = null);
      return;
    }
    attempts.sort((a, b) {
      final aTime = a.completedAt?.millisecondsSinceEpoch ?? 0;
      final bTime = b.completedAt?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });
    setState(() => _lastScore = attempts.first.overallScore);
  }

  Future<void> _loadLatestAttempt() async {
    // Ensure attempts are loaded from database
    await _attempts.ensureLoaded();
    if (!mounted) return;
    // Query most recent session by exerciseId (resilient to re-entry)
    final latest = _attempts.latestFor(widget.exerciseId);
    setState(() {
      _latestAttempt = latest;
    });
  }

  Future<void> _loadProgress({bool showToast = false}) async {
    final progress = await _levelProgress.getExerciseProgress(widget.exerciseId);
    if (!mounted) return;
    final previousHighest = _highestUnlockedLevel;
    final nextHighest = progress.highestUnlockedLevel;
    var nextSelected = _selectedLevel;
    if (!_progressLoaded || nextSelected > nextHighest || nextSelected < 1) {
      final preferred = progress.lastSelectedLevel;
      if (preferred != null &&
          preferred >= ExerciseLevelProgress.minLevel &&
          preferred <= nextHighest) {
        nextSelected = preferred;
      } else {
        nextSelected = nextHighest;
      }
    } else if (showToast && nextHighest > previousHighest && nextSelected == previousHighest) {
      nextSelected = nextHighest;
    }
    final levelUp = showToast && nextHighest > previousHighest;
    setState(() {
      _highestUnlockedLevel = nextHighest;
      _bestScoresByLevel = progress.bestScoreByLevel;
      _progressLoaded = true;
      _highlightedLevel = levelUp ? nextHighest : null;
      _selectedLevel = nextSelected;
    });
    // Removed duplicate _triggerPreparation() as it's handled by postFrame and manual updates
    if (levelUp && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Level up! Level $nextHighest unlocked.')),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() => _highlightedLevel = null);
      });
    }
  }

  void _triggerPreparation() async {
    final exercise = ExerciseRepository().getExercise(widget.exerciseId);
    final difficulty = pitchHighwayDifficultyFromLevel(_selectedLevel);
    
    // Fast-path: Check cache first
    final cached = await ReferenceAudioGenerator.instance.tryGetCached(exercise, difficulty);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _planFuture = Future.value(cached);
          _preparing = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _preparing = true;
        _planFuture = ReferenceAudioGenerator.instance.prepare(exercise, difficulty).then((plan) {
          if (mounted) {
            setState(() => _preparing = false);
          }
          return plan;
        }).catchError((e) {
          if (mounted) {
            setState(() => _preparing = false);
          }
          throw e;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final exercise = _repo.getExercise(widget.exerciseId);
    // Use estimated duration (pattern × range for pitch-highway); show as approximate, rounded to nearest half minute
    final estimatedSec = exercise.estimatedDurationSec;
    final timeChip = estimatedSec > 0
        ? HomeCategoryBannerRow.formatDurationApproximate(estimatedSec)
        : (exercise.reps != null ? '${exercise.reps} reps' : '—');
    final typeLabel = _typeLabel(exercise.type);
    final isPitchHighway = exercise.type == ExerciseType.pitchHighway;
    final metadata = ExerciseMetadata.forExercise(exercise);
    final canPreviewAudio = metadata.previewSupported;
    final canReview = isPitchHighway && _latestAttempt != null;
    final selectionLocked = isPitchHighway && _selectedLevel > _highestUnlockedLevel;
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
            _SectionHeader(title: 'Difficulty Level'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(3, (index) {
                final level = index + 1;
                final unlocked = level <= _highestUnlockedLevel;
                final selected = _selectedLevel == level;
                final highlighted = _highlightedLevel == level;
                final best = _bestScoresByLevel[level];
                final label = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Level $level'),
                    if (!unlocked) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.lock, size: 14, color: Colors.grey[600]),
                    ],
                  ],
                );
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: highlighted ? Colors.amber.withOpacity(0.2) : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChoiceChip(
                        label: label,
                        selected: selected,
                        onSelected: unlocked
                            ? (_) {
                                setState(() => _selectedLevel = level);
                                _levelProgress.setLastSelectedLevel(
                                  exerciseId: widget.exerciseId,
                                  level: level,
                                );
                              }
                            : null,
                        labelStyle: unlocked
                            ? null
                            : Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(color: Colors.grey[500]),
                      ),
                      if (best != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Best $best%',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey[600]),
                          ),
                        ),
                      if (!unlocked)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Score 90%+ on previous level to unlock',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey[600]),
                          ),
                        ),
                    ],
                  ),
                );
              }),
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
            onPressed: selectionLocked || _preparing
                ? null
                : () async {
                    final tapTime = DateTime.now();
                    debugPrint('[StartExercise] tapped at ${tapTime.millisecondsSinceEpoch}');
                    await _previewAudio.stop();
                    
                    if (isPitchHighway) {
                      setState(() => _preparing = true);
                    }
                    
                    try {
                      await _startExercise(exercise);
                    } finally {
                      if (mounted) {
                        setState(() => _preparing = false);
                      }
                    }
                    
                    await _loadLastScore();
                    await _loadLatestAttempt();
                    await _loadProgress(showToast: true);
                  },
            icon: _preparing 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow),
            label: Text(_preparing ? 'Preparing...' : 'Start Exercise'),
          ),
          if (exercise.type == ExerciseType.pitchHighway) ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: canReview
                  ? () {
                      // Navigate directly to Detailed Review (ExerciseReviewSummaryScreen)
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ExerciseReviewSummaryScreen(
                            exercise: exercise,
                            attempt: _latestAttempt!,
                          ),
                        ),
                      );
                    }
                  : null,
              icon: const Icon(Icons.replay),
              label: const Text('Review last take'),
            ),
            if (!canReview)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'No take recorded yet.',
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
    final startTime = DateTime.now();
    debugPrint('[StartExercise] _startExercise called at ${startTime.millisecondsSinceEpoch}');
    
    final selectedDifficulty = pitchHighwayDifficultyFromLevel(_selectedLevel);
    
    if (exercise.type == ExerciseType.pitchHighway) {
      // Navigate immediately
      unawaited(_levelProgress.setLastSelectedLevel(
        exerciseId: widget.exerciseId,
        level: _selectedLevel,
      ));
      
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExercisePlayerScreen(
              exercise: exercise,
              pitchDifficulty: selectedDifficulty,
              exercisePlanFuture: _planFuture,
            ),
          ),
        );
      }
      return;
    }
    
    // For non-pitchHighway exercises, navigate immediately
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => buildExerciseScreen(
          exercise,
          pitchDifficulty: selectedDifficulty,
        ),
      ),
    );
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
    debugPrint('[Preview] start - exercise=${exercise.id}');
    
    try {
      final metadata = ExerciseMetadata.forExercise(exercise);
      
      // Check if preview is supported
      if (!metadata.previewSupported) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No preview available for this exercise.')),
          );
        }
        return;
      }

      // Use the new preview audio service (loads bundled assets or generates real-time)
      await _previewAudio.playPreview(exercise);
    } catch (e) {
      debugPrint('[Preview] error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Preview failed: $e')),
        );
      }
    }
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
