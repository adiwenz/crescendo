import 'package:flutter/material.dart';

import '../../data/seed_library.dart';
import '../../design/app_colors.dart';
import '../../design/app_text.dart';
import '../../models/category.dart';
import '../../routing/exercise_route_registry.dart';
import '../../widgets/home/continue_card.dart';
import '../../widgets/home/home_category_banner_row.dart';
import '../../widgets/home/home_hero_header.dart';
import '../explore/category_detail_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Category> categories = seedLibraryCategories();
    final warmup = seedExercisesFor('warmup').firstOrNull;
    final pitch = seedExercisesFor('pitch').firstOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const _HomeHero(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Continue', style: AppText.h2),
                      const Icon(Icons.chevron_right,
                          color: AppColors.textSecondary),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 140,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        if (warmup != null)
                          ContinueCard(
                            title: 'Warmup',
                            subtitle: '2 min left',
                            progress: 0.35,
                            pillText: 'Session in progress',
                            bannerStyleId: warmup.bannerStyleId,
                            onTap: () =>
                                _openExercise(context, warmup.id, warmup.title),
                          ),
                        if (pitch != null)
                          ContinueCard(
                            title: 'Pitch Slides',
                            subtitle: 'Level 2',
                            progress: 0.65,
                            bannerStyleId: pitch.bannerStyleId,
                            onTap: () =>
                                _openExercise(context, pitch.id, pitch.title),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Train Your Voice', style: AppText.h2),
                      const Icon(Icons.chevron_right,
                          color: AppColors.textSecondary),
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

  void _openExercise(BuildContext context, String id, String title) {
    final entry = ExerciseRouteRegistry.entryFor(id);
    if (entry != null) {
      Navigator.push(context, MaterialPageRoute(builder: entry.builder));
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Not wired yet'),
        content: Text('Exercise $title is not wired to a screen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero();

  @override
  Widget build(BuildContext context) {
    return const HomeHeroHeader(
      title: 'Welcome',
      subtitle: 'Let\'s train your voice',
    );
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
