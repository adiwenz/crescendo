import 'package:flutter/material.dart';
import '../../../../theme/ballad_theme.dart';
import '../../../../widgets/ballad_buttons.dart';

class OnboardingCard extends StatelessWidget {
  final String title;
  final String? body;
  final Widget? bodyWidget;
  final Widget visual;
  final VoidCallback onContinue;
  final String ctaText;

  const OnboardingCard({
    super.key,
    required this.title,
    this.body,
    this.bodyWidget,
    required this.visual,
    required this.onContinue,
    this.ctaText = 'Continue',
  }) : assert(body != null || bodyWidget != null, 'Must provide either body text or bodyWidget');

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Layer 1: Visual
        Positioned.fill(
          child: visual,
        ),

        // Layer 2: Text Content
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                // Top: Title
                const SizedBox(height: 80),
                Text(
                  title,
                  style: BalladTheme.titleLarge.copyWith(height: 1.2),
                  textAlign: TextAlign.center,
                ),
                
                const Spacer(flex: 1),
                
                // Middle: Body
                Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: bodyWidget ?? Text(
                    body!,
                    style: BalladTheme.bodyMedium.copyWith(
                      fontSize: 20, 
                      height: 1.5,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                const Spacer(),

                // Bottom: CTA
                SizedBox(
                  width: double.infinity,
                  child: BalladPrimaryButton(
                    onPressed: onContinue,
                    label: ctaText,
                  ),
                ),
                const SizedBox(height: 60), 
              ],
            ),
          ),
        ),
      ],
    );
  }
}
