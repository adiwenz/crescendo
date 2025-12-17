import 'package:flutter/material.dart';

class FindRangeScreen extends StatelessWidget {
  const FindRangeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Find Your Range'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Find Your Range',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Placeholder content. This will guide you through a short test to estimate your vocal range.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: () {},
              child: const Text('Start'),
            ),
          ],
        ),
      ),
    );
  }
}
