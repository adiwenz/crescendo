import 'package:flutter/material.dart';

import '../../data/seed_library.dart';
import '../../widgets/banner_card.dart';
import 'category_detail_screen.dart';

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = seedLibraryCategories();
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Explore', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('Find the right exercise', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            ...categories.map((c) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: BannerCard(
                  title: c.title,
                  subtitle: c.subtitle,
                  bannerStyleId: c.bannerStyleId,
                  trailing: const Icon(Icons.chevron_right, color: Colors.black54),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CategoryDetailScreen(category: c),
                      ),
                    );
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
