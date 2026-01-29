import 'package:flutter/material.dart';

import '../../models/vocal_exercise.dart';
import '../../models/exercise_attempt.dart';
import '../../routing/exercise_route_registry.dart';
import '../../services/attempt_repository.dart';
import '../../services/exercise_level_progress_repository.dart';
import '../../services/exercise_repository.dart';
import '../../widgets/banner_card.dart';
import '../../ui/screens/exercise_review_summary_screen.dart';
import '../../services/preview_audio_service.dart';
import '../../services/exercise_metadata.dart';
import 'dart:async';
import '../../ui/route_observer.dart';
import '../../models/exercise_level_progress.dart';
import '../../models/pitch_highway_difficulty.dart';
import '../../models/exercise_plan.dart';
import '../../services/reference_audio_generator.dart';
import '../../utils/navigation_trace.dart';

class ExercisePreviewScreen extends StatefulWidget {
  final String exerciseId;
  final NavigationTrace? trace;

  const ExercisePreviewScreen({super.key, required this.exerciseId, this.trace});

  @override
  State<ExercisePreviewScreen> createState() => _ExercisePreviewScreenState();
}

class _ExercisePreviewScreenState extends State<ExercisePreviewScreen>
    with RouteAware {
  final ExerciseRepository _repo = ExerciseRepository.instance;
  final AttemptRepository _attempts = AttemptRepository.instance;
  final ExerciseLevelProgressRepository _levelProgress =
      ExerciseLevelProgressRepository();
      
  PreviewAudioService? _previewAudio;
  VocalExercise? _exercise;
  String _categoryTitle = '';
  int _bannerStyleId = 0;
  
  ExerciseAttemptInfo? _latest;
  bool _loading = true;
  bool _previewing = false;
  int _highestUnlockedLevel = ExerciseLevelProgress.minLevel;
  int _selectedLevel = ExerciseLevelProgress.minLevel;
  int? _highlightedLevel;
  Map<int, int> _bestScoresByLevel = const <int, int>{};
  bool _progressLoaded = false;
  Future<ExercisePlan>? _planFuture;
  bool _isPreparing = false;

  @override
  void initState() {
    super.initState();
    widget.trace?.mark('ExercisePreview initState');
    // Requirements: Defer heavy generation until after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.trace?.markFirstFrame();
        _load(); // Start loading all data after first frame
        
        // Initialize audio service after first frame
        _previewAudio = PreviewAudioService();
      }
    });
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
    _previewAudio?.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    debugPrint('[Preview] didPopNext triggered, reloading...');
    _load();
  }

  Future<void> _load() async {
    widget.trace?.mark('_load start');
    
    // 1. Get Exercise Definition
    final ex = _repo.getExercise(widget.exerciseId);
    
    // 2. Compute Metadata (previously in build)
    final category = _repo.getCategory(ex.categoryId);
    final categoryTitle = category.title;
    final bannerStyleId = category.sortOrder % 8;
    
    // 3. Load Level Progress
    final progress = await _levelProgress.getExerciseProgress(widget.exerciseId, forceRefresh: true);
    
    // 4. Load Last Score
    final lastScore = await _attempts.fetchLastScore(widget.exerciseId);
    
    if (!mounted) return;
    
    // 5. Batch State Update (One setState)
    setState(() {
      _exercise = ex;
      _categoryTitle = categoryTitle;
      _bannerStyleId = bannerStyleId;
      
      // Progress data

      final nextHighest = progress.highestUnlockedLevel;
      _highestUnlockedLevel = nextHighest;
      _bestScoresByLevel = progress.bestScoreByLevel;
      _progressLoaded = true;
      
      // Select level logic
      if (_selectedLevel > nextHighest || _selectedLevel < ExerciseLevelProgress.minLevel) {
          final preferred = progress.lastSelectedLevel;
          if (preferred != null && preferred >= ExerciseLevelProgress.minLevel && preferred <= nextHighest) {
            _selectedLevel = preferred;
          } else {
            _selectedLevel = nextHighest;
          }
      }
      
      // Last score data
      if (lastScore != null) {
        final attempt = ExerciseAttempt(
          id: lastScore.id,
          exerciseId: lastScore.exerciseId,
          categoryId: lastScore.categoryId,
          completedAt: lastScore.createdAt,
          overallScore: lastScore.score,
          startedAt: null,
        );
        _latest = ExerciseAttemptInfo.fromAttempt(attempt);
      } else {
        _latest = null;
      }
      
      _loading = false;
    });
    
    widget.trace?.mark('_load complete (setState)');
    
    // Trigger audio preparation after state is stable
    _triggerPreparation();
  }

  void _triggerPreparation() async {
    // ... (rest of method unchanged)
    final ex = _exercise;
    if (ex == null) return;
    
    final difficulty = pitchHighwayDifficultyFromLevel(_selectedLevel);
    
    // Fast-path: Check cache first to avoid flicker/delay
    final cached = await ReferenceAudioGenerator.instance.tryGetCached(ex, difficulty);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _planFuture = Future.value(cached);
          _isPreparing = false;
        });
      }
      return;
    }

    // Cache miss: start full preparation
    if (mounted) {
      setState(() {
        _isPreparing = true;
        _planFuture = ReferenceAudioGenerator.instance.prepare(ex, difficulty).then((plan) {
          if (mounted) {
            setState(() => _isPreparing = false);
          }
          return plan;
        }).catchError((e) {
          if (mounted) {
            setState(() => _isPreparing = false);
          }
          throw e;
        });
      });
    }
  }

  Future<void> _refreshLatest() async {
    widget.trace?.mark('_refreshLatest start');
    // Force re-fetch from repository/DB to ensure we get the latest write
    final lastScore = await _attempts.fetchLastScore(widget.exerciseId);
    
    if (!mounted) return;
    setState(() {
      if (lastScore != null) {
        final attempt = ExerciseAttempt(
          id: lastScore.id,
          exerciseId: lastScore.exerciseId,
          categoryId: lastScore.categoryId,
          completedAt: lastScore.createdAt,
          overallScore: lastScore.score,
          startedAt: null,
        );
        _latest = ExerciseAttemptInfo.fromAttempt(attempt);
      } else {
        _latest = null;
      }
    });
    widget.trace?.mark('_refreshLatest complete');
  }

  Future<void> _refreshProgress({bool showToast = false}) async {
    // Force refresh from DB to get latest updates
    final progress = await _levelProgress.getExerciseProgress(widget.exerciseId, forceRefresh: true);
    
    if (!mounted) return;
    
    final previousHighest = _highestUnlockedLevel;
    final nextHighest = progress.highestUnlockedLevel;
    
    // Debug logging as requested
    debugPrint('[PreviewRefresh] exerciseId=${widget.exerciseId} progressHighest=$nextHighest selected=$_selectedLevel');
    debugPrint('[PreviewRefresh] bestScores=${progress.bestScoreByLevel}');
    
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
    
    // Log computed best for current level
    final currentBest = _bestScoresByLevel[_selectedLevel];
    debugPrint('[PreviewRefresh] Updated UI for level $_selectedLevel. Best: $currentBest%');

    // Plan refresh will be triggered by WidgetsBinding or manual selection if it changes
    // But since it's a value change, we should trigger it here too if it's already past the first frame
    if (_progressLoaded) {
       _triggerPreparation();
    }
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
    widget.trace?.mark('build start (loading=$_loading)');
    
    final ex = _exercise;
    // Use pre-computed title
    final appBarBuild = AppBar(title: Text(_categoryTitle.isNotEmpty ? _categoryTitle : 'Exercise'));

    final body = _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (ex != null) 
                  _Header(
                    ex: ex, 
                    bannerStyleId: _bannerStyleId
                  ),
                const SizedBox(height: 16),
                Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Purpose',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(ex?.purpose ??
                            ex?.description ??
                            'Build control and accuracy.'),
                        const SizedBox(height: 16),
                        const Text('How it works',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(ex?.description ??
                            'Follow along and match the guide.'),
                      ],
                    ),
                  ),
                ),
                if (ex != null &&
                    ExerciseMetadata.forExercise(ex).previewSupported) ...[
                  const SizedBox(height: 16),
                  Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Preview',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Text(ex.description),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              ElevatedButton.icon(
                                onPressed:
                                    _previewing ? null : () => _playPreview(ex),
                                icon: Icon(_previewing
                                    ? Icons.pause
                                    : Icons.play_arrow),
                                label: Text(
                                    _previewing ? 'Playing…' : 'Play preview'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (ex?.usesPitchHighway == true) ...[
                  const SizedBox(height: 16),
                  Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Difficulty',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
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
                              final difficulty =
                                  pitchHighwayDifficultyFromLevel(level);
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: highlighted
                                      ? Colors.amber.withOpacity(0.2)
                                      : Colors.transparent,
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
                                            Icon(Icons.lock,
                                                size: 14,
                                                color: Colors.grey[600]),
                                          ],
                                        ],
                                      ),
                                      selected: selected,
                                      onSelected: unlocked
                                          ? (_) async {
                                              setState(
                                                  () => _selectedLevel = level);
                                              await _levelProgress
                                                  .setLastSelectedLevel(
                                                exerciseId: widget.exerciseId,
                                                level: level,
                                              );
                                              _triggerPreparation(); // Refresh plan for new level
                                            }
                                          : null,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      pitchHighwayDifficultySpeedLabel(
                                          difficulty),
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
                          if (_highestUnlockedLevel <
                              ExerciseLevelProgress.maxLevel)
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
                        onPressed: _isPreparing ? null : _startExercise,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Start Exercise'),
                              if (_isPreparing) ...[
                                const SizedBox(height: 4),
                                const Text(
                                  'Preparing audio...',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.normal),
                                ),
                              ],
                            ],
                          ),
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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      title: Text(
                          'Last score: ${_latest!.score.toStringAsFixed(0)}'),
                      subtitle: Text('Completed ${_latest!.dateLabel}'),
                    ),
                  ),
              ],
            );

    return Scaffold(
      appBar: appBarBuild,
      body: body,
    );
  }

  Future<void> _startExercise() async {
    // Stop preview immediately when starting exercise
    await _previewAudio?.stop();
    if (mounted) {
      setState(() {
        _previewing = false;
      });
    }

    if (_exercise?.usesPitchHighway == true) {
      unawaited(_levelProgress.setLastSelectedLevel(
        exerciseId: widget.exerciseId,
        level: _selectedLevel,
      ));
    }

    final opened = ExerciseRouteRegistry.open(
      context,
      widget.exerciseId,
      difficultyLevel: _selectedLevel,
      exercisePlanFuture: _planFuture,
    );

    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exercise not wired yet')),
      );
      return;
    }
    // Wait for the route to pop, then refresh data
    await Future.delayed(const Duration(milliseconds: 300));
    
    debugPrint('[Preview] Returned from exercise, refreshing data...');
    // Explicitly reload all data (progress + attempts)
    await _load();
  }

  Future<void> _reviewLast() async {
    final ex = _exercise;
    if (ex == null) return;
    
    // Get ID from the lightweight attempt we have
    final currentLite = _latest;
    if (currentLite == null) return;
    
    // Fetch full 
    // We already have some info, but reviews might need full DB object
    // Since we don't have global cache anymore, we'll try to find it
    // AttemptRepository.latestFor will fail if we haven't loaded cache.
    // Instead we can just open the review screen with what we have? 
    // Review screen takes `ExerciseAttempt`. The one we constructed in _load is partial.
    // But ExerciseReviewSummaryScreen might fetch details if needed?
    // Actually, `ExerciseReviewSummaryScreen` usually expects a full object or it just displays stats.
    // Let's reload the specific attempt by ID if we can.
    
    // If we only have score/date, we don't have the ID?
    // fetchLastScore DOES return ID (empty string in my imp? NO, I should fix that).
    
    // Wait, ProgressRepository.fetchLastScore returns empty ID?
    // id: '', // Not needed
    // I should fix ProgressRepository to return the actual ID if possible, but take_scores table has ID.
    // Yes, take_scores has ID.
    
    // Assuming I fix ProgressRepository to return ID (I will in next step):
    
    var attempt = currentLite.raw;
    
    // Inspect if we need to load more data
    // If it's a "lite" object (startedAt is null), we might want full object.
    // But for now, let's try to pass what we have.
    // Actually, ExerciseReviewSummaryScreen might need recording path?
    // The lite object has null recordingPath.
    
    // Let's try to fetch full attempt if ID is valid
    if (attempt.id.isNotEmpty) {
      final full = await _attempts.getFullAttempt(attempt.id);
      if (full != null) {
        attempt = full;
      }
    }

    if (!mounted) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseReviewSummaryScreen(
          exercise: ex,
          attempt: attempt,
        ),
      ),
    );
  }

  Future<void> _playPreview(VocalExercise ex) async {
    if (_previewing) return; // Prevent multiple simultaneous previews

    setState(() => _previewing = true);
    debugPrint('[Preview] start - exercise=${ex.id}');

    try {
      final metadata = ExerciseMetadata.forExercise(ex);

      // Check if preview is supported
      if (!metadata.previewSupported) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No preview available for this exercise')),
          );
        }
        return;
      }

      // Use the new preview audio service (loads bundled assets or generates real-time)
      if (_previewAudio != null) {
        await _previewAudio!.playPreview(ex);
      } else {
         debugPrint('[Preview] previewAudio not initialized yet');
         _previewAudio = PreviewAudioService();
         await _previewAudio!.playPreview(ex);
      }
    } catch (e) {
      debugPrint('[Preview] error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Preview failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _previewing = false);
      }
    }
  }
}

class _Header extends StatelessWidget {
  final VocalExercise ex;
  final int bannerStyleId;

  const _Header({required this.ex, required this.bannerStyleId});

  @override
  Widget build(BuildContext context) {
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
            bannerStyleId: bannerStyleId,
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
      completedAt:
          attempt.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
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
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    if (m < 1 || m > 12) return '';
    return names[m - 1];
  }
}
