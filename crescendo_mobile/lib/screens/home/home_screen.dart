import 'package:flutter/material.dart';

import '../../data/seed_library.dart';
import '../../design/app_text.dart';
import '../../models/category.dart';
import '../../widgets/home/home_category_banner_row.dart';
import '../explore/category_detail_screen.dart';
import 'styles.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Category> categories = seedLibraryCategories();

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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Today\'s Progress', style: AppText.h2),
                  const SizedBox(height: 12),
                  _TodaysProgressCard(),
                  const SizedBox(height: 24),
                  Text('Today\'s Exercises', style: AppText.h2),
                  const SizedBox(height: 12),
                  _ExercisesWithProgressIndicator(
                    exercises: _categoryRows(context, categories),
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

  List<Widget> _categoryRows(BuildContext context, List<Category> categories) {
    final mapped = {
      'warmup': {'title': 'Warmup', 'subtitle': 'Ease in with gentle starters'},
      'program': {
        'title': 'Exercise from your program',
        'subtitle': 'Core exercises from your plan'
      },
      'pitch': {'title': 'Pitch Accuracy', 'subtitle': 'Dial in your center'},
      'agility': {'title': 'Agility', 'subtitle': 'Move quickly and cleanly'},
    };

    return categories.where((c) => mapped.containsKey(c.id)).map<Widget>(
      (c) {
        final info = mapped[c.id]!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: HomeCategoryBannerRow(
            title: info['title']!,
            subtitle: info['subtitle']!,
            bannerStyleId: c.bannerStyleId,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => CategoryDetailScreen(category: c)),
            ),
          ),
        );
      },
    ).toList();
  }
}

class _ExercisesWithProgressIndicator extends StatelessWidget {
  final List<Widget> exercises;

  const _ExercisesWithProgressIndicator({required this.exercises});

  @override
  Widget build(BuildContext context) {
    if (exercises.isEmpty) return const SizedBox.shrink();

    // TODO: Replace with actual completion data from progress repository
    // Mock completion states for demonstration
    final completionStates = [true, true, false, false]; // First 2 completed, last 2 incomplete

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress indicator column (line + circles)
        SizedBox(
          width: 24, // Fixed width for progress indicator area
          child: Stack(
            children: [
              // Vertical progress line - connects all circles
              if (exercises.length > 1)
                Positioned(
                  left: 7, // Center of 16px circle (8px radius)
                  top: 8, // Start from center of first circle
                  bottom: 8, // End at center of last circle
                  child: Container(
                    width: 2,
                    decoration: BoxDecoration(
                      color: HomeScreenStyles.iconInactive.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              // Progress circles
              Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(exercises.length, (index) {
                  final isCompleted = index < completionStates.length
                      ? completionStates[index]
                      : false;
                  return SizedBox(
                    height: 96 + 16, // Card height (96) + bottom padding (16)
                    child: Align(
                      alignment: Alignment.center,
                      child: _ProgressCircle(isCompleted: isCompleted),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
        // Exercise cards column
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: exercises,
          ),
        ),
      ],
    );
  }
}

class _ProgressCircle extends StatelessWidget {
  final bool isCompleted;

  const _ProgressCircle({required this.isCompleted});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCompleted
            ? HomeScreenStyles.accentPurple
            : Colors.transparent,
        border: Border.all(
          color: isCompleted
              ? HomeScreenStyles.accentPurple
              : HomeScreenStyles.iconInactive.withOpacity(0.5),
          width: 2,
        ),
      ),
      child: isCompleted
          ? const Icon(
              Icons.check,
              size: 10,
              color: Colors.white,
            )
          : null,
    );
  }
}

class _TodaysProgressCard extends StatelessWidget {
  const _TodaysProgressCard();

  @override
  Widget build(BuildContext context) {
    // TODO: Replace with actual data from progress repository
    final todaysProgress = 0.45; // 45% complete
    final minutesLeft = 12; // 12 minutes left to practice

    return Container(
      decoration: BoxDecoration(
        color: HomeScreenStyles.cardFill.withOpacity(HomeScreenStyles.cardOpacity),
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
                    '$minutesLeft min left to practice',
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
              valueColor: const AlwaysStoppedAnimation<Color>(HomeScreenStyles.progressBarFill),
            ),
          ),
        ],
      ),
    );
  }
}
