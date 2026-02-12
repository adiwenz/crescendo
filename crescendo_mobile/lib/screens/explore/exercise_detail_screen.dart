import 'package:flutter/material.dart';

import '../../models/exercise.dart';
import '../../state/library_store.dart';
import '../../widgets/abstract_banner_painter.dart';
import '../../widgets/ballad_scaffold.dart';
import '../../widgets/frosted_panel.dart';
import '../../widgets/ballad_buttons.dart';
import '../../theme/ballad_theme.dart';
import 'exercise_session_screen.dart';

class ExerciseDetailScreen extends StatelessWidget {
  final Exercise exercise;

  const ExerciseDetailScreen({super.key, required this.exercise});

  @override
  Widget build(BuildContext context) {
    return BalladScaffold(
      title: exercise.title,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        children: [
          SizedBox(
            height: 200,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              // Use a frosted container for the banner to blend better? 
              // Or keep it as is if it's an image/painter.
              // AbstractBannerPainter paints on CustomPaint.
              // Let's keep it but maybe wrap in a slightly transparent card if needed.
              // The original Card had clip antiAlias.
              child: CustomPaint(painter: AbstractBannerPainter(exercise.bannerStyleId)),
            ),
          ),
          const SizedBox(height: 24),
          
          FrostedPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exercise.title, 
                  style: BalladTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                Text(
                  '${exercise.subtitle}\n\nFocus on clean onsets, relaxed airflow, and centering your pitch.',
                  style: BalladTheme.bodyMedium.copyWith(color: BalladTheme.textSecondary),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          
          BalladPrimaryButton(
            label: 'Start Exercise',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExerciseSessionScreen(exercise: exercise),
                ),
              );
              await libraryStore.save();
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }
}
