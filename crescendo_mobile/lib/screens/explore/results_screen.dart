import 'package:flutter/material.dart';

class ResultsScreen extends StatelessWidget {
  final double score;
  final String exerciseId;

  const ResultsScreen({
    super.key,
    required this.score,
    required this.exerciseId,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (score / 100).clamp(0.0, 1.0);
    return Scaffold(
      appBar: AppBar(title: const Text('Results')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: pct,
                    strokeWidth: 10,
                    backgroundColor: Colors.black12,
                  ),
                  Text('${score.toStringAsFixed(0)}%'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Exercise complete', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.popUntil(context, (route) => route.isFirst || route.settings.name == '/explore');
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
