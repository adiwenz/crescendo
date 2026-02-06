import 'package:flutter/material.dart';
import '../../../../design/app_colors.dart';
import '../../../../design/app_text.dart';

class OnboardingCard extends StatelessWidget {
  final String title;
  final String? body; // Made optional
  final Widget? bodyWidget; // New custom widget option
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
    // Using LayoutBuilder to manage the split intelligently
    return LayoutBuilder(
      builder: (context, constraints) {
        
        return Column(
          children: [
             // visual takes up available space, but at least 40% of screen to look good
            Expanded(
              flex: 4, 
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                child: visual,
              ),
            ),
             // Text area takes remaining space (flex 5 = ~55%). 
             // We use SingleChildScrollView inside to be absolutely safe against overflow.
            Expanded(
              flex: 5,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end, // Push content down if there's extra space
                  children: [
                    // Flexible content area that can scroll
                     Flexible(
                       child: SingleChildScrollView(
                         child: Column(
                           mainAxisSize: MainAxisSize.min,
                           children: [
                             const SizedBox(height: 16),
                             Text(
                               title,
                               style: AppText.h1.copyWith(fontSize: 28, height: 1.2),
                               textAlign: TextAlign.center,
                             ),
                             const SizedBox(height: 16),
                             if (bodyWidget != null)
                               bodyWidget!
                             else
                               Text(
                                 body!,
                                 style: AppText.body.copyWith(fontSize: 16, height: 1.5, color: AppColors.textSecondary.withOpacity(0.8)),
                                 textAlign: TextAlign.center,
                               ),
                             const SizedBox(height: 24),
                           ],
                         ),
                       ),
                     ),
                    // Button always at the bottom of this section
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: onContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          elevation: 4,
                          shadowColor: AppColors.accent.withOpacity(0.4),
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
                    const SizedBox(height: 48), // Bottom padding
                  ],
                ),
              ),
            ),
          ],
        );
      }
    );
  }
}
