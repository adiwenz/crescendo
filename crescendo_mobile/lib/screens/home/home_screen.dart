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
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                      categories: categories,
                      context: context,
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
  final List<Category> categories;
  final BuildContext context;

  const _ExercisesWithProgressIndicator({
    required this.categories,
    required this.context,
  });

  @override
  Widget build(BuildContext context) {
    final mapped = {
      'warmup': {'title': 'Warmup', 'subtitle': 'Ease in with gentle starters'},
      'program': {
        'title': 'Exercise from your program',
        'subtitle': 'Core exercises from your plan'
      },
      'pitch': {'title': 'Pitch Accuracy', 'subtitle': 'Dial in your center'},
      'agility': {'title': 'Agility', 'subtitle': 'Move quickly and cleanly'},
    };

    final categoryList =
        categories.where((c) => mapped.containsKey(c.id)).toList();
    if (categoryList.isEmpty) return const SizedBox.shrink();

    // TODO: Replace with actual completion data from progress repository
    // Mock completion states for demonstration
    final completionStates = [true, true, true]; // All completed for now

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
    final int lastRowIndex = categoryList.length - 1;
    final double lastRowTop = lastRowIndex * (cardHeight + cardSpacing);
    final double lastCircleCenterY = lastRowTop + (cardHeight / 2);

    // Line starts at first circle center and extends all the way to last circle center
    // Extend by half the circle radius to ensure it visually reaches the bottom circle center
    const double circleRadius = TimelineIcon._size / 2; // 16.0
    final double lineTop = firstCircleCenterY;
    final double lineHeight = (lastCircleCenterY - firstCircleCenterY) +
        circleRadius; // Extend to ensure visual reach

    return Stack(
      children: [
        // Vertical connector line - positioned between first and last circle centers only
        if (categoryList.length > 1 && lineHeight > 0)
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
          children: List.generate(categoryList.length, (index) {
            final c = categoryList[index];
            final info = mapped[c.id]!;
            final isCompleted = index < completionStates.length
                ? completionStates[index]
                : false;

            return Padding(
              padding: EdgeInsets.only(
                  bottom: index < categoryList.length - 1 ? cardSpacing : 0),
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
                        title: info['title']!,
                        subtitle: info['subtitle']!,
                        bannerStyleId: c.bannerStyleId,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  CategoryDetailScreen(category: c)),
                        ),
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
  const _TodaysProgressCard();

  @override
  Widget build(BuildContext context) {
    // TODO: Replace with actual data from progress repository
    final todaysProgress = 0.45; // 45% complete
    final minutesLeft = 12; // 12 minutes left to practice

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
              valueColor: const AlwaysStoppedAnimation<Color>(
                  HomeScreenStyles.progressBarFill),
            ),
          ),
        ],
      ),
    );
  }
}
