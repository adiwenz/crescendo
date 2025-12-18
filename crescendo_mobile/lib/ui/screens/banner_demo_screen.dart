import 'package:flutter/material.dart';
import '../../widgets/banner_card.dart';
import '../../widgets/exercise_row_banner.dart';

class BannerDemoScreen extends StatelessWidget {
  const BannerDemoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Banner Demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const BannerCard(
            title: 'Warmup',
            subtitle: 'Gentle ease-in patterns',
            bannerStyleId: 0,
            trailing: Icon(Icons.chevron_right),
          ),
          const SizedBox(height: 16),
          const BannerCard(
            title: 'Pitch Accuracy',
            subtitle: 'Center your tone',
            bannerStyleId: 2,
            trailing: Icon(Icons.check_circle, color: Colors.green),
          ),
          const SizedBox(height: 24),
          const ExerciseRowBanner(
            title: 'Scale 1',
            subtitle: 'Up and down 5-note',
            bannerStyleId: 1,
            completed: true,
          ),
          const SizedBox(height: 12),
          const ExerciseRowBanner(
            title: 'Glide 2',
            subtitle: 'Smooth siren glide',
            bannerStyleId: 3,
            completed: false,
          ),
        ],
      ),
    );
  }
}
