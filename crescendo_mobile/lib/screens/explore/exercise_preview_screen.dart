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
import '../../services/vocal_range_service.dart';
import '../../audio/ref_audio/wav_cache_manager.dart';
import '../../audio/ref_audio/ref_spec.dart';
import '../../utils/navigation_trace.dart';
import '../../widgets/ballad_scaffold.dart';
import '../../widgets/frosted_panel.dart';
import '../../widgets/ballad_buttons.dart';
import '../../theme/ballad_theme.dart';

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
    
    // Fetch range for spec
    // TODO: Ideally pass this from _load or value notifier to avoid async gap if possible, 
    // but looking it up here is safe enough.
    final (low, high) = await VocalRangeService().getRange();

    final spec = RefSpec(
      exerciseId: ex.id,
      lowMidi: low,
      highMidi: high,
      extraOptions: {'difficulty': difficulty.name},
      renderVersion: 'v2',
    );
    
    // WavCacheManager handles cache check + generation queue
    // It returns a future that completes when the plan/file is ready
    // Unlike ReferenceAudioGenerator, we don't need a separate "tryGetCached" check
    // because WavCacheManager does that internally and returns fast if hit.
    
    if (mounted) {
      setState(() {
        _isPreparing = true;
        _planFuture = WavCacheManager.instance.get(spec, exercise: ex).then((plan) {
          if (mounted) {
            setState(() => _isPreparing = false);
          }
          return plan;
        }).catchError((e) {
          if (mounted) {
            setState(() => _isPreparing = false);
          }
          throw e; // Propagate error to FutureBuilder
        });
        
        // Optimistic update: check if we can skip the loading spinner immediately
        // if the future completes synchronously/microtask (cache hit)
        // Actually WavCacheManager.get is async, but if it hits cache it's very fast.
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
    final title = _categoryTitle.isNotEmpty ? _categoryTitle : 'Exercise';

    final body = _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              children: [
                if (ex != null) 
                  _Header(
                    ex: ex, 
                    bannerStyleId: _bannerStyleId
                  ),
                const SizedBox(height: 16),
                FrostedPanel(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Purpose', style: BalladTheme.bodyLarge.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(ex?.purpose ?? ex?.description ?? 'Build control and accuracy.', style: BalladTheme.bodyMedium),
                      const SizedBox(height: 16),
                      Text('How it works', style: BalladTheme.bodyLarge.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(ex?.description ?? 'Follow along and match the guide.', style: BalladTheme.bodyMedium),
                    ],
                  ),
                ),
                if (ex != null &&
                    ExerciseMetadata.forExercise(ex).previewSupported) ...[
                  const SizedBox(height: 16),
                  const SizedBox(height: 16),
                  FrostedPanel(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Preview', style: BalladTheme.bodyLarge.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(ex.description, style: BalladTheme.bodyMedium),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            IntrinsicWidth(
                              child: BalladPrimaryButton(
                                onPressed: _previewing ? null : () => _playPreview(ex),
                                icon: _previewing ? Icons.pause : Icons.play_arrow,
                                label: _previewing ? 'Playing…' : 'Play preview',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                if (ex?.usesPitchHighway == true) ...[
                  const SizedBox(height: 16),
                  FrostedPanel(
                    borderRadius: BorderRadius.circular(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Difficulty', style: BalladTheme.bodyLarge.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
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
                            
                            return GestureDetector(
                              onTap: unlocked
                                  ? () async {
                                      setState(() => _selectedLevel = level);
                                      await _levelProgress.setLastSelectedLevel(
                                        exerciseId: widget.exerciseId,
                                        level: level,
                                      );
                                      _triggerPreparation();
                                    }
                                  : null,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  color: selected 
                                      ? BalladTheme.accentTeal.withOpacity(0.2) 
                                      : (highlighted ? BalladTheme.accentGold.withOpacity(0.2) : Colors.white.withOpacity(0.05)),
                                  border: Border.all(
                                    color: selected 
                                        ? BalladTheme.accentTeal 
                                        : (highlighted ? BalladTheme.accentGold : Colors.white.withOpacity(0.2)),
                                    width: 1.5,
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Level $level',
                                          style: BalladTheme.bodyMedium.copyWith(
                                            color: selected || highlighted ? Colors.white : Colors.white70,
                                            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                        if (!unlocked) ...[
                                          const SizedBox(width: 6),
                                          const Icon(Icons.lock, size: 14, color: Colors.white38),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      pitchHighwayDifficultySpeedLabel(difficulty),
                                      style: BalladTheme.bodySmall.copyWith(color: Colors.white54),
                                    ),
                                    if (best != null)
                                      Text(
                                        'Best: $best%',
                                        style: BalladTheme.bodySmall.copyWith(color: BalladTheme.accentTeal),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                        if (_highestUnlockedLevel < ExerciseLevelProgress.maxLevel)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, size: 16, color: Colors.white54),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Score 90%+ to unlock next level.',
                                    style: BalladTheme.bodySmall.copyWith(color: Colors.white54),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: BalladPrimaryButton(
                        onPressed: _isPreparing ? null : _startExercise,
                        label: _isPreparing ? 'Preparing audio...' : 'Start Exercise',
                        isLoading: _isPreparing,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: BalladPrimaryButton(
                        label: 'Review last take',
                        onPressed: _latest == null ? null : _reviewLast,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_latest != null) ...[
                  const SizedBox(height: 16),
                  FrostedPanel(
                    padding: EdgeInsets.zero, // ListTile has its own padding
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      title: Text(
                          'Last score: ${_latest!.score.toStringAsFixed(0)}',
                          style: BalladTheme.bodyLarge,
                      ),
                      subtitle: Text(
                          'Completed ${_latest!.dateLabel}',
                          style: BalladTheme.bodyMedium.copyWith(color: BalladTheme.textSecondary),
                      ),
                      trailing: Icon(Icons.history, color: BalladTheme.textSecondary),
                    ),
                  ),
                ],
              ],
            );

    return BalladScaffold(
      title: title,
      child: body,
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
    debugPrint('[Preview] _reviewLast triggered');
    try {
      final ex = _exercise;
      if (ex == null) {
        debugPrint('[Preview] _reviewLast blocked: ex is null');
        return;
      }
      
      // Get ID from the lightweight attempt we have
      final currentLite = _latest;
      if (currentLite == null) {
        debugPrint('[Preview] _reviewLast blocked: currentLite is null');
        return;
      }
      
      var attempt = currentLite.raw;
      debugPrint('[Preview] _reviewLast processing attempt id=${attempt.id}');
      
      // Let's try to fetch full attempt if ID is valid
      if (attempt.id.isNotEmpty) {
        debugPrint('[Preview] _reviewLast fetching full attempt...');
        try {
          final full = await _attempts.getFullAttempt(attempt.id);
          if (full != null) {
            debugPrint('[Preview] _reviewLast full attempt found');
            attempt = full;
          } else {
            debugPrint('[Preview] _reviewLast full attempt NOT found');
          }
        } catch (e) {
          debugPrint('[Preview] Warning: Failed to fetch full attempt: $e');
          // Fallback to existing attempt data
        }
      } else {
        debugPrint('[Preview] _reviewLast attempt ID is empty, using lite object');
      }

      if (!mounted) {
         debugPrint('[Preview] _reviewLast aborted: not mounted');
         return;
      }
      
      debugPrint('[Preview] _reviewLast pushing ExerciseReviewSummaryScreen. ID=${attempt.id} Type=${ex.type}');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExerciseReviewSummaryScreen(
            exercise: ex,
            attempt: attempt,
          ),
        ),
      );
    } catch (e, stack) {
      debugPrint('[Preview] _reviewLast ERROR: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to open review: $e')),
        );
      }
    }
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
          style: BalladTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        // Description
        Text(
          ex.description,
          style: BalladTheme.bodyMedium,
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
