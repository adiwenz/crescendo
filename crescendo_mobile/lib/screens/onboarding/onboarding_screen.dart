import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/ballad_scaffold.dart';
import '../../theme/ballad_theme.dart';
import 'widgets/onboarding_card.dart';
import 'widgets/onboarding_visuals.dart';
import 'widgets/onboarding_wave_painter.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  final List<Widget> _visuals = const [
    WelcomeVisual(),
    WhyVisual(),
    HowItWorksVisual(), // New glowing swoops visual
    GetStartedVisual(),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentIndex < 3) {
      _pageController.animateToPage(
        _currentIndex + 1,
        duration: const Duration(milliseconds: 600), // Slower, smoother transition
        curve: Curves.easeInOutCubic, // "Gentle" curve
      );
    } else {
      _finishOnboarding();
    }
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seenOnboarding', true);

    if (!mounted) return;
    // Navigate to home or initial route
    // Using simple replacement for now, usually updates a persistent "seenOnboarding" pref
    Navigator.of(context).pushReplacementNamed('/');
  }

  @override
  Widget build(BuildContext context) {
    final bulletPointStyle = BalladTheme.bodyMedium.copyWith(
      fontSize: 20, 
      height: 1.5, 
      color: Colors.white.withOpacity(0.9)
    );

    return BalladScaffold(
      title: 'Welcome',
      // We use BalladScaffold for the background, but we want full control over the body stack
      // BalladScaffold puts child in SafeArea by default if we don't say otherwise, 
      // but here we want the visuals to stretch. 
      // Actually BalladScaffold wraps child in SafeArea(bottom: false).
      // We can use the stack here.
      child: Stack(
        children: [
          // 1. Animated Visuals (Original Drawings)
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              child: KeyedSubtree(
                key: ValueKey<int>(_currentIndex),
                child: _visuals[_currentIndex],
              ),
            ),
          ),

          // 2. Wave Visual (Bottom)
          Positioned.fill(
            child: CustomPaint(
              painter: OnboardingWavePainter(color: Colors.white),
            ),
          ),

          // 3. Content
          Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                  children: [
                    // Screen 1: Welcome
                    OnboardingCard(
                      title: 'Welcome to Crescendo!',
                      body: 'Crescendo is a voice training app designed to make singing feel easier.\n\nIt helps your voice warm up, stay steady, and move freely so singing is a breeze.',
                      visual: const SizedBox.shrink(), // Visual is in stack
                      onContinue: _nextPage,
                    ),
                    // Screen 2: Why Exercises Help
                    OnboardingCard(
                      title: 'Why exercises help',
                      // Using bodyWidget for custom alignment
                      bodyWidget: Column(
                        children: [
                          // Constrained width container to make left-aligned bullets look centered
                          Container(
                            constraints: const BoxConstraints(maxWidth: 300),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'They help your voice:',
                                  style: bulletPointStyle,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 30),
                                _buildBulletPoint('Find notes faster', bulletPointStyle),
                                _buildBulletPoint('Stay in tune', bulletPointStyle),
                                _buildBulletPoint('Reduce tension', bulletPointStyle),
                                _buildBulletPoint('Learn technique', bulletPointStyle),
                              ],
                            ),
                          ),
                          const SizedBox(height: 30),
                          Text(
                            'So when you sing, it feels more reliable.',
                            style: bulletPointStyle,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                      visual: const SizedBox.shrink(), // Visual is in stack
                      onContinue: _nextPage,
                    ),
                    // Screen 3: How Crescendo Works
                    OnboardingCard(
                      title: 'How Crescendo works',
                      body: 'Crescendo guides you through daily exercises and listens as you sing, helping you notice what’s working in real time — without pressure.',
                      visual: const SizedBox.shrink(), // Visual is in stack
                      onContinue: _nextPage,
                    ),
                    // Screen 4: Let's Get Started
                    OnboardingCard(
                      title: 'So let’s get singing!',
                      body: 'Start where you are, learn more about your voice, and have fun.',
                      visual: const SizedBox.shrink(), // Visual is in stack
                      ctaText: 'Start Singing', // Different CTA
                      onContinue: _finishOnboarding,
                    ),
                  ],
                ),
              ),
              // Page Indicator dots (Minimal chrome)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    return GestureDetector(
                      onTap: () {
                        _pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeInOutCubic,
                        );
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 8,
                        width: _currentIndex == index ? 24 : 8,
                        decoration: BoxDecoration(
                          color: _currentIndex == index 
                              ? Colors.white 
                              : Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(String text, TextStyle style) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: style),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}
