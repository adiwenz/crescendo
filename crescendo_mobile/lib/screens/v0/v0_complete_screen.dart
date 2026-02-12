import 'package:flutter/material.dart';
import '../../widgets/ballad_scaffold.dart';
import '../../widgets/frosted_panel.dart';
import '../../widgets/ballad_buttons.dart';
import '../../theme/ballad_theme.dart';

class V0CompleteScreen extends StatelessWidget {
  const V0CompleteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BalladScaffold(
      title: "Complete",
      showBack: false,
      child: Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: FrostedPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: BalladTheme.accentTeal.withOpacity(0.2), // Success Greenish/Teal
                      shape: BoxShape.circle,
                      border: Border.all(color: BalladTheme.accentTeal.withOpacity(0.5), width: 2),
                      boxShadow: [
                         BoxShadow(
                             color: BalladTheme.accentTeal.withOpacity(0.4),
                             blurRadius: 20,
                             spreadRadius: 2
                         )
                      ]
                    ),
                    child: const Icon(Icons.check, color: BalladTheme.accentTeal, size: 40),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "Session Complete",
                    style: BalladTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Great work today!",
                    style: BalladTheme.bodyLarge.copyWith(
                      color: BalladTheme.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  BalladPrimaryButton(
                      label: "Done", 
                      onPressed: () {
                        // Navigate back to V0 Home (root)
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      }
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
        ),
      ),
    );
  }
}
