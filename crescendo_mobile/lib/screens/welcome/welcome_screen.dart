import 'package:flutter/material.dart';

import '../../data/seed_library.dart';
import '../../widgets/banner_card.dart';
import '../explore/category_detail_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = seedLibraryCategories().take(4).toList();
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Welcome', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            ...categories.map(
              (c) => Padding(
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
