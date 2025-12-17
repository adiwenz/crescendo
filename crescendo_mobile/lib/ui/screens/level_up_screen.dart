import 'package:flutter/material.dart';

import '../../models/pitch_highway_difficulty.dart';

class LevelUpScreen extends StatelessWidget {
  final String exerciseName;
  final int score;
  final PitchHighwayDifficulty? unlockedDifficulty;

  const LevelUpScreen({
    super.key,
    required this.exerciseName,
    required this.score,
    this.unlockedDifficulty,
  });

  @override
  Widget build(BuildContext context) {
    final unlockedLabel = unlockedDifficulty != null
        ? '${pitchHighwayDifficultyLabel(unlockedDifficulty!)} unlocked'
        : 'Great work!';
    return Scaffold(
      body: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(24),
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Level Up!',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'You scored $score% — $unlockedLabel',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                exerciseName,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
