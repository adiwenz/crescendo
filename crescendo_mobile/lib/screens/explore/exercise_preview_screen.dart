import 'package:flutter/material.dart';

import '../../models/vocal_exercise.dart';
import '../../models/exercise_attempt.dart';
import '../../routing/exercise_route_registry.dart';
import '../../services/attempt_repository.dart';
import '../../services/exercise_level_progress_repository.dart';
import '../../services/exercise_repository.dart';
import '../../services/audio_synth_service.dart';
import '../../widgets/banner_card.dart';
import '../../ui/screens/exercise_review_summary_screen.dart';
import '../../models/reference_note.dart';
import 'dart:math' as math;
import '../../ui/route_observer.dart';
import '../../models/exercise_level_progress.dart';
import '../../models/pitch_highway_difficulty.dart';
import '../../utils/pitch_highway_tempo.dart';

class ExercisePreviewScreen extends StatefulWidget {
  final String exerciseId;

  const ExercisePreviewScreen({super.key, required this.exerciseId});

  @override
  State<ExercisePreviewScreen> createState() => _ExercisePreviewScreenState();
}

class _ExercisePreviewScreenState extends State<ExercisePreviewScreen> with RouteAware {
  final ExerciseRepository _repo = ExerciseRepository();
  final AttemptRepository _attempts = AttemptRepository.instance;
  final ExerciseLevelProgressRepository _levelProgress =
      ExerciseLevelProgressRepository();
  final AudioSynthService _synth = AudioSynthService();
  VocalExercise? _exercise;
  ExerciseAttemptInfo? _latest;
  bool _loading = true;
  bool _previewing = false;
  int _highestUnlockedLevel = ExerciseLevelProgress.minLevel;
  int _selectedLevel = ExerciseLevelProgress.minLevel;
  int? _highlightedLevel;
  Map<int, int> _bestScoresByLevel = const <int, int>{};
  bool _progressLoaded = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[Preview] exerciseId=${widget.exerciseId}');
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _synth.stop();
    super.dispose();
  }

  @override
  void didPopNext() {
    _refreshLatest();
    _refreshProgress(showToast: true);
  }

  Future<void> _load() async {
    final ex = _repo.getExercises().firstWhere(
      (e) => e.id == widget.exerciseId,
      orElse: () => _repo.getExercises().first,
    );
    await _refreshProgress();
    // Only ensure loaded, don't refresh - use cache which is already up to date
    await _attempts.ensureLoaded();
    final latest = _attempts.latestFor(widget.exerciseId);
    if (latest == null) {
      debugPrint('[Preview] latest attempt not found for ${widget.exerciseId}');
    }
    if (!mounted) return;
    setState(() {
      _exercise = ex;
      _latest = latest == null ? null : ExerciseAttemptInfo.fromAttempt(latest);
      _loading = false;
    });
  }

  Future<void> _refreshLatest() async {
    // Use cache - it's already updated by AttemptRepository.save()
    // No need to refresh from database
    final latest = _attempts.latestFor(widget.exerciseId);
    if (!mounted) return;
    setState(() {
      _latest = latest == null ? null : ExerciseAttemptInfo.fromAttempt(latest);
    });
  }

  Future<void> _refreshProgress({bool showToast = false}) async {
    final progress = await _levelProgress.getExerciseProgress(widget.exerciseId);
    if (!mounted) return;
    final previousHighest = _highestUnlockedLevel;
    final nextHighest = progress.highestUnlockedLevel;
    var nextSelected = _selectedLevel;
    if (!_progressLoaded ||
        nextSelected > nextHighest ||
        nextSelected < ExerciseLevelProgress.minLevel) {
      final preferred = progress.lastSelectedLevel;
      if (preferred != null &&
          preferred >= ExerciseLevelProgress.minLevel &&
          preferred <= nextHighest) {
        nextSelected = preferred;
      } else {
        nextSelected = nextHighest;
      }
    }
    final levelUp = showToast && nextHighest > previousHighest;
    setState(() {
      _highestUnlockedLevel = nextHighest;
      _bestScoresByLevel = progress.bestScoreByLevel;
      _progressLoaded = true;
      _highlightedLevel = levelUp ? nextHighest : null;
      _selectedLevel = nextSelected;
    });
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

  @override
  Widget build(BuildContext context) {
    final ex = _exercise;
    // Get category name for AppBar
    String? categoryTitle;
    if (ex != null) {
      try {
        categoryTitle = _repo.getCategory(ex.categoryId).title;
      } catch (e) {
        // Fallback if category not found
      }
    }
    return Scaffold(
      appBar: AppBar(title: Text(categoryTitle ?? 'Exercise')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (ex != null) _Header(ex: ex),
                const SizedBox(height: 16),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Purpose', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(ex?.purpose ?? ex?.description ?? 'Build control and accuracy.'),
                        const SizedBox(height: 16),
                        const Text('How it works', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(ex?.description ?? 'Follow along and match the guide.'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Preview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(ex?.description ?? 'A quick preview of the exercise.'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _previewing || ex == null ? null : () => _playPreview(ex),
                              icon: Icon(_previewing ? Icons.pause : Icons.play_arrow),
                              label: Text(_previewing ? 'Playing…' : 'Play preview'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (ex?.usesPitchHighway == true) ...[
                  const SizedBox(height: 16),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Difficulty', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
                              final difficulty = pitchHighwayDifficultyFromLevel(level);
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
                                      label: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('Level $level'),
                                          if (!unlocked) ...[
                                            const SizedBox(width: 6),
                                            Icon(Icons.lock, size: 14, color: Colors.grey[600]),
                                          ],
                                        ],
                                      ),
                                      selected: selected,
                                      onSelected: unlocked
                                          ? (_) async {
                                              setState(() => _selectedLevel = level);
                                              await _levelProgress.setLastSelectedLevel(
                                                exerciseId: widget.exerciseId,
                                                level: level,
                                              );
                                            }
                                          : null,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      pitchHighwayDifficultySpeedLabel(difficulty),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.grey[600]),
                                    ),
                                    if (best != null)
                                      Text(
                                        'Best: $best%',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: Colors.grey[600]),
                                      ),
                                  ],
                                ),
                              );
                            }),
                          ),
                          if (_highestUnlockedLevel < ExerciseLevelProgress.maxLevel)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Score 90%+ on the previous level to unlock.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey[600]),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _startExercise,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text('Start Exercise'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _latest == null ? null : _reviewLast,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text('Review last take'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_latest != null)
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      title: Text('Last score: ${_latest!.score.toStringAsFixed(0)}'),
                      subtitle: Text('Completed ${_latest!.dateLabel}'),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _startExercise() async {
    // Stop preview immediately when starting exercise
    await _synth.stop();
    if (mounted) {
      setState(() => _previewing = false);
    }
    
    if (_exercise?.usesPitchHighway == true) {
      await _levelProgress.setLastSelectedLevel(
        exerciseId: widget.exerciseId,
        level: _selectedLevel,
      );
    }
    final opened = ExerciseRouteRegistry.open(
      context,
      widget.exerciseId,
      difficultyLevel: _selectedLevel,
    );
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exercise not wired yet')),
      );
      return;
    }
    await Future.delayed(const Duration(milliseconds: 300));
    // Cache is already updated by AttemptRepository.save()
    // No need to refresh from database
    final latest = _attempts.latestFor(widget.exerciseId);
    if (mounted) {
      setState(() => _latest = latest == null ? null : ExerciseAttemptInfo.fromAttempt(latest));
    }
  }

  void _reviewLast() {
    final ex = _exercise;
    // Query most recent session by exerciseId from database (resilient to re-entry)
    final latest = _attempts.latestFor(widget.exerciseId);
    if (latest == null || ex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No take recorded yet.')),
      );
      return;
    }
    // Navigate directly to Detailed Review (ExerciseReviewSummaryScreen)
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseReviewSummaryScreen(
          exercise: ex,
          attempt: latest,
        ),
      ),
    );
  }

  Future<void> _playPreview(VocalExercise ex) async {
    setState(() => _previewing = true);
    try {
      // If we have a highway spec, render a short preview. Otherwise show message.
      if (ex.highwaySpec == null || ex.highwaySpec!.segments.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No preview available for this exercise')),
        );
        return;
      }
      final difficulty = pitchHighwayDifficultyFromLevel(_selectedLevel);
      final multiplier = PitchHighwayTempo.multiplierFor(
        difficulty,
        ex.highwaySpec!.segments,
      );
      // Use synth to render a short preview from the first few segments.
      final scaledSegments = PitchHighwayTempo.scaleSegments(
        ex.highwaySpec!.segments,
        multiplier,
      );
      final segments = scaledSegments.take(8).toList();
      final notes = segments
          .take(8)
          .map((s) => ReferenceNote(
                startSec: s.startMs / 1000.0,
                endSec: s.endMs / 1000.0,
                midi: s.midiNote,
              ))
          .toList();
      final totalDurationMs =
          segments.isEmpty ? 0 : segments.map((s) => s.endMs).reduce(math.max) - segments.first.startMs;
      final path = await _synth.renderReferenceNotes(notes);
      await _synth.playFile(path);
      // Ensure the button stays in the "playing" state for the full preview duration.
      if (totalDurationMs > 0) {
        await Future.delayed(Duration(milliseconds: totalDurationMs + 300));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preview failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }
}

class _Header extends StatelessWidget {
  final VocalExercise ex;
  final ExerciseRepository _repo = ExerciseRepository();
  
  _Header({required this.ex});

  @override
  Widget build(BuildContext context) {
    // Get the category to use its sortOrder for consistent colors
    final category = _repo.getCategory(ex.categoryId);
    final bannerStyleId = category.sortOrder % 8;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Exercise name as header
        Text(
          ex.name,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        // Description
        Text(
          ex.description,
          style: Theme.of(context).textTheme.bodyMedium,
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 140,
          child: BannerCard(
            title: ex.name,
            subtitle: ex.description,
            bannerStyleId: bannerStyleId, // Use category's color
          ),
        ),
      ],
    );
  }
}

class ExerciseAttemptInfo {
  final double score;
  final DateTime completedAt;
  final String? recordingPath;
  final ExerciseAttempt raw;

  ExerciseAttemptInfo({
    required this.score,
    required this.completedAt,
    required this.recordingPath,
    required this.raw,
  });

  factory ExerciseAttemptInfo.fromAttempt(ExerciseAttempt attempt) {
    return ExerciseAttemptInfo(
      score: attempt.overallScore,
      completedAt: attempt.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      recordingPath: attempt.recordingPath,
      raw: attempt,
    );
  }

  String get dateLabel {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(completedAt.year, completedAt.month, completedAt.day);
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    return '${_month(completedAt.month)} ${completedAt.day}';
  }

  String _month(int m) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (m < 1 || m > 12) return '';
    return names[m - 1];
  }
}
