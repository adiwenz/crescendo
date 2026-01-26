import 'dart:async';
import 'package:flutter/material.dart';

import '../../design/app_text.dart';
import '../../models/exercise.dart';
import '../../screens/explore/exercise_preview_screen.dart';
import '../../services/daily_exercise_service.dart';
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

    // Calculate line positions
    final double firstCircleCenterY = cardHeight / 2;
    final int lastRowIndex = exercises!.length - 1;
    final double lastRowTop = lastRowIndex * (cardHeight + cardSpacing);
    final double lastCircleCenterY = lastRowTop + (cardHeight / 2);

    const double circleRadius = TimelineIcon._size / 2; // 16.0
    final double lineTop = firstCircleCenterY;
    final double lastCircleBottom = lastCircleCenterY + circleRadius;
    final double lineHeight = lastCircleBottom - firstCircleCenterY;

    return Stack(
      children: [
        // Vertical connector line
        if (exercises!.length > 1 && lineHeight > 0)
          Positioned(
            left: (gutterWidth / 2) - 0.75, // Center of gutter
            top: lineTop, // Start at first circle center
            child: Container(
              width: 1.5,
              height: lineHeight,
              decoration: BoxDecoration(
                color: mutedLineColor,
                borderRadius: BorderRadius.circular(0.75),
              ),
            ),
          ),
        // Column of rows
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
                        subtitle: '',
                        bannerStyleId: exercise.bannerStyleId,
                        onTap: () {
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

class TimelineIcon extends StatelessWidget {
  final bool isCompleted;
  static const double _size = 32.0;

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
            ? HomeScreenStyles.timelineCheckmarkBackground
            : Colors.white,
        border: Border.all(
          color: isCompleted
              ? HomeScreenStyles.timelineCheckmarkBackground
              : HomeScreenStyles.iconInactive.withOpacity(0.4),
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

    final minutesLeft = dailyExercises != null && dailyExercises!.isNotEmpty
        ? dailyExerciseService.calculateRemainingMinutes(
            dailyExercises!, completedIds)
        : 0;

    final totalExercises = dailyExercises?.length ?? 0;
    final completedCount = totalExercises > 0
        ? dailyExercises!.where((e) => completedIds.contains(e.id)).length
        : 0;
    final todaysProgress =
        totalExercises > 0 ? completedCount / totalExercises : 0.0;

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
