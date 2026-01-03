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
      body: SafeArea(
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Today\'s Progress', style: AppText.h2),
                      const Icon(Icons.chevron_right,
                          color: HomeScreenStyles.iconInactive),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _TodaysProgressCard(),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Today\'s Exercises', style: AppText.h2),
                      const Icon(Icons.chevron_right,
                          color: HomeScreenStyles.iconInactive),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._categoryRows(context, categories),
                ],
              ),
            ),
          ],
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
