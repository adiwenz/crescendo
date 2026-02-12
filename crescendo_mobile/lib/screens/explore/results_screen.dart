import 'package:flutter/material.dart';
import '../../widgets/ballad_scaffold.dart';
import '../../widgets/frosted_panel.dart';
import '../../widgets/ballad_buttons.dart';
import '../../theme/ballad_theme.dart';

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
    return BalladScaffold(
      title: 'Results',
      showBack: false, // Don't allow back to session
      child: Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: FrostedPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: pct,
                          strokeWidth: 10,
                          backgroundColor: Colors.white12,
                          color: BalladTheme.accentTeal, // Use theme accent
                        ),
                        Text(
                            '${score.toStringAsFixed(0)}%',
                            style: BalladTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                      'Exercise complete', 
                      style: BalladTheme.titleMedium,
                  ),
                  const SizedBox(height: 32),
                  BalladPrimaryButton(
                    label: 'Continue',
                    onPressed: () {
                      Navigator.popUntil(context, (route) => route.isFirst || route.settings.name == '/explore');
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
        ),
      ),
    );
  }
}
