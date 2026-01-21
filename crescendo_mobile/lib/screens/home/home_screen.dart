import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../../design/app_text.dart';
import '../../models/exercise.dart';
import '../../screens/explore/exercise_preview_screen.dart';
import '../../services/daily_exercise_service.dart';
import '../../services/sync_diagnostic_service.dart';
import '../../state/library_store.dart';
import '../../widgets/home/home_category_banner_row.dart';
import 'styles.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Exercise>? _dailyExercises;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDailyExercises();
    // Listen to completion changes
    libraryStore.addListener(_onCompletionChanged);
  }

  @override
  void dispose() {
    libraryStore.removeListener(_onCompletionChanged);
    super.dispose();
  }

  void _onCompletionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadDailyExercises() async {
    final exercises = await dailyExerciseService.getTodaysExercises();
    if (mounted) {
      setState(() {
        _dailyExercises = exercises;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: HomeScreenStyles.homeScreenGradient,
        ),
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome',
                      style: AppText.h1.copyWith(fontSize: 28),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Let\'s train your voice',
                      style: AppText.body.copyWith(fontSize: 15),
                    ),
                  ],
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Today\'s Progress', style: AppText.h2),
                    const SizedBox(height: 12),
                    _TodaysProgressCard(dailyExercises: _dailyExercises),
                    const SizedBox(height: 24),
                    Text('Today\'s Exercises', style: AppText.h2),
                    const SizedBox(height: 12),
                    _ExercisesWithProgressIndicator(
                      exercises: _dailyExercises,
                      isLoading: _isLoading,
                    ),
                    // Debug section (only in debug mode)
                    if (kDebugMode) ...[
                      const SizedBox(height: 24),
                      _DebugSection(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Debug section with sync diagnostic button
/// 
/// How to use:
/// 1. Tap "Run Sync Diagnostic" button
/// 2. Test runs: 2s lead-in, then plays a sharp click at t=2.0s, records for 5s total
/// 3. After recording, analyzes WAV to find click onset
/// 4. Computes offsetMs = detectedClickMs - scheduledClickMs (2000ms)
/// 5. Saves offsetMs to SharedPreferences for use in review playback compensation
/// 
/// Interpreting offsetMs:
/// - Positive offsetMs: recorded audio is LATE relative to scheduled reference (MIDI plays too early)
/// - Negative offsetMs: recorded audio is EARLY relative to scheduled reference (MIDI plays too late)
/// - Typical values: 0-100ms (good sync), 100-300ms (noticeable drift), >300ms (significant issue)
class _DebugSection extends StatefulWidget {
  const _DebugSection();

  @override
  State<_DebugSection> createState() => _DebugSectionState();
}

class _DebugSectionState extends State<_DebugSection> {
  bool _running = false;
  String? _statusMessage;
  int? _savedOffset;

  @override
  void initState() {
    super.initState();
    _loadSavedOffset();
  }

  Future<void> _loadSavedOffset() async {
    final offset = await SyncDiagnosticService.getSavedOffset();
    if (mounted) {
      setState(() {
        _savedOffset = offset;
      });
    }
  }

  Future<void> _runDiagnostic() async {
    if (_running) return;

    setState(() {
      _running = true;
      _statusMessage = 'Running diagnostic...';
    });

    try {
      final offsetMs = await SyncDiagnosticService.runDiagnostic();
      
      if (mounted) {
        setState(() {
          _running = false;
          if (offsetMs != null) {
            _statusMessage = 'Offset: ${offsetMs}ms';
            _savedOffset = offsetMs;
          } else {
            _statusMessage = 'Diagnostic failed - check logs';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _statusMessage = 'Error: $e';
        });
      }
    }
  }

  Future<void> _clearOffset() async {
    await SyncDiagnosticService.clearSavedOffset();
    if (mounted) {
      setState(() {
        _savedOffset = null;
        _statusMessage = 'Offset cleared';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Debug Tools',
            style: AppText.h2.copyWith(color: Colors.red.shade700),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _running ? null : _runDiagnostic,
            child: Text(_running ? 'Running...' : 'Run Sync Diagnostic'),
          ),
          if (_savedOffset != null) ...[
            const SizedBox(height: 8),
            Text(
              'Saved offset: ${_savedOffset}ms',
              style: AppText.body.copyWith(fontSize: 12),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _clearOffset,
              child: const Text('Clear Offset'),
            ),
          ],
          if (_statusMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _statusMessage!,
              style: AppText.body.copyWith(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExercisesWithProgressIndicator extends StatelessWidget {
  final List<Exercise>? exercises;
  final bool isLoading;

  const _ExercisesWithProgressIndicator({
    required this.exercises,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (exercises == null || exercises!.isEmpty) {
      return const SizedBox.shrink();
    }

    final completedIds = libraryStore.completedExerciseIds;

    const double gutterWidth = 48.0; // Fixed-width timeline gutter
    const double cardSpacing = 16.0; // Bottom padding between cards
    const double cardHeight = 96.0; // Card height (from HomeCategoryBannerRow)
    final mutedLineColor = HomeScreenStyles.iconInactive.withOpacity(0.3);

    // Calculate line positions: start at first circle center, end at last circle center
    // Each row has height = cardHeight, with cardSpacing between rows
    // Circle centers are at cardHeight/2 from the top of each row
    final double firstCircleCenterY =
        cardHeight / 2; // Center of first row (index 0)

    // Calculate the exact position of the last circle center
    // For n items: row 0 at 0, row 1 at (cardHeight + cardSpacing), etc.
    // Last row (index n-1) starts at: (n-1) * (cardHeight + cardSpacing)
    final int lastRowIndex = exercises!.length - 1;
    final double lastRowTop = lastRowIndex * (cardHeight + cardSpacing);
    final double lastCircleCenterY = lastRowTop + (cardHeight / 2);

    // Line starts at first circle center and extends all the way to last circle center
    // Extend to the bottom edge of the last circle to ensure it connects fully
    const double circleRadius = TimelineIcon._size / 2; // 16.0
    final double lineTop = firstCircleCenterY;
    final double lastCircleBottom = lastCircleCenterY + circleRadius;
    final double lineHeight = lastCircleBottom - firstCircleCenterY;

    return Stack(
      children: [
        // Vertical connector line - positioned between first and last circle centers only
        if (exercises!.length > 1 && lineHeight > 0)
          Positioned(
            left: (gutterWidth / 2) - 0.75, // Center of gutter
            top: lineTop, // Start at first circle center
            child: Container(
              width: 1.5,
              height: lineHeight, // Height from first to last circle center
              decoration: BoxDecoration(
                color: mutedLineColor,
                borderRadius: BorderRadius.circular(0.75),
              ),
            ),
          ),
        // Column of rows - each row contains icon + card
        Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(exercises!.length, (index) {
            final exercise = exercises![index];
            final isCompleted = completedIds.contains(exercise.id);

            return Padding(
              padding: EdgeInsets.only(
                  bottom: index < exercises!.length - 1 ? cardSpacing : 0),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left: Timeline gutter with icon
                    SizedBox(
                      width: gutterWidth,
                      child: Center(
                        child: TimelineIcon(isCompleted: isCompleted),
                      ),
                    ),
                    // Right: Exercise card
                    Expanded(
                      child: HomeCategoryBannerRow(
                        title: exercise.title,
                        subtitle: '', // Not used, but required by widget
                        bannerStyleId: exercise.bannerStyleId,
                        onTap: () {
                          // Navigate to the exercise preview screen
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ExercisePreviewScreen(
                                  exerciseId: exercise.id),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

enum TimelineIconStatus {
  completed,
  incomplete,
  current,
}

class TimelineIcon extends StatelessWidget {
  final bool isCompleted;
  static const double _size = 32.0; // Circle size

  const TimelineIcon({
    super.key,
    required this.isCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCompleted
            ? HomeScreenStyles
                .timelineCheckmarkBackground // Color from HomeScreenStyles
            : Colors
                .white, // White background to cover the line behind incomplete circles
        border: Border.all(
          color: isCompleted
              ? HomeScreenStyles.timelineCheckmarkBackground
              : HomeScreenStyles.iconInactive
                  .withOpacity(0.4), // Muted gray/lavender for incomplete
          width: isCompleted ? 0 : 2,
        ),
      ),
      child: isCompleted
          ? const Icon(
              Icons.check_rounded,
              size: 20,
              color: Colors.white,
            )
          : null,
    );
  }
}

class _TodaysProgressCard extends StatelessWidget {
  final List<Exercise>? dailyExercises;

  const _TodaysProgressCard({this.dailyExercises});

  @override
  Widget build(BuildContext context) {
    final completedIds = libraryStore.completedExerciseIds;

    // Calculate remaining time
    final minutesLeft = dailyExercises != null && dailyExercises!.isNotEmpty
        ? dailyExerciseService.calculateRemainingMinutes(
            dailyExercises!, completedIds)
        : 0;

    // Calculate progress percentage
    final totalExercises = dailyExercises?.length ?? 0;
    final completedCount = totalExercises > 0
        ? dailyExercises!.where((e) => completedIds.contains(e.id)).length
        : 0;
    final todaysProgress =
        totalExercises > 0 ? completedCount / totalExercises : 0.0;

    // Format remaining time text
    String remainingTimeText;
    if (minutesLeft <= 0) {
      remainingTimeText = 'All done for today 🎉';
    } else if (minutesLeft < 1) {
      remainingTimeText = '<1 min left';
    } else {
      remainingTimeText = '$minutesLeft min left to practice';
    }

    return Container(
      decoration: BoxDecoration(
        color:
            HomeScreenStyles.cardFill.withOpacity(HomeScreenStyles.cardOpacity),
        borderRadius: BorderRadius.circular(HomeScreenStyles.cardBorderRadius),
        border: Border.all(
          color: HomeScreenStyles.cardBorder,
          width: HomeScreenStyles.cardBorderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: HomeScreenStyles.cardShadowColor,
            blurRadius: HomeScreenStyles.cardShadowBlur,
            spreadRadius: HomeScreenStyles.cardShadowSpread,
            offset: HomeScreenStyles.cardShadowOffset,
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${(todaysProgress * 100).round()}% Complete',
                    style: HomeScreenStyles.cardTitle.copyWith(fontSize: 20),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    remainingTimeText,
                    style: HomeScreenStyles.cardSubtitle,
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: HomeScreenStyles.accentPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.trending_up,
                  color: HomeScreenStyles.accentPurple,
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: todaysProgress.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: HomeScreenStyles.progressBarBackground,
              valueColor: const AlwaysStoppedAnimation<Color>(
                  HomeScreenStyles.progressBarFill),
            ),
          ),
        ],
      ),
    );
  }
}
