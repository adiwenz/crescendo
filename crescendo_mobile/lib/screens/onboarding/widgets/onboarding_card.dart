import 'package:flutter/material.dart';
import '../../../../design/app_colors.dart';
import '../../../../design/app_text.dart';

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
    // New layout: Title Top, Body Middle, CTA Bottom.
    // We use a Stack to let the Visual inhabit the space freely (likely middle/background),
    // while the text content is strictly positioned.
    return Stack(
      children: [
        // Layer 1: Visual
        // We let the visual fill the space, or we could center it.
        // Given the painters use "size.height * 0.x", filling the screen allows them to draw relative to full height.
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
                const SizedBox(height: 40), // Top spacing
                Text(
                  title,
                  style: AppText.h1.copyWith(
                    fontSize: 32, // Larger/Cleaner
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    // color: Colors.white, // REVERTED: Background is light (#dfbdfe), so text must be dark.
                  ),
                  textAlign: TextAlign.center,
                ),
                
                // Spacer to push Body to middle
                const Spacer(),
                
                // Middle: Body
                // We wrap in a container to ensure it doesn't span too wide
                Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: bodyWidget ?? Text(
                    body!,
                    style: AppText.body.copyWith(
                      fontSize: 18, // Slightly larger for readability
                      height: 1.5,
                      color: AppColors.textPrimary.withOpacity(0.8),
                      // fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                // Spacer to push CTA to bottom
                const Spacer(),

                // Bottom: CTA
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: onContinue,
                    style: ElevatedButton.styleFrom(
                      // Let's use the Accent color as it's the primary action.
                      backgroundColor: AppColors.accent, 
                      foregroundColor: Colors.white,
                      elevation: 0, // Flat/Modern
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: Text(
                      ctaText,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 60), // Space for bottom dots and safe area
              ],
            ),
          ),
        ),
      ],
    );
  }
}
