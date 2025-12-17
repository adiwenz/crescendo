import 'package:flutter/material.dart';

class SubscriptionFeaturesScreen extends StatelessWidget {
  const SubscriptionFeaturesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final features = [
      'Full exercise library access',
      'Personalized warmups (placeholder)',
      'Pitch tracking and scoring',
      'Progress charts and history',
      'Offline downloads (placeholder)',
      'Priority support (placeholder)',
    ];
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Subscription Features'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Unlock more with premium',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ...features.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• '),
                    Expanded(
                      child: Text(
                        f,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: () {},
              child: const Text('Start free trial'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to Subscription'),
            ),
          ],
        ),
      ),
    );
  }
}
