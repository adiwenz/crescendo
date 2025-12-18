import 'package:flutter/material.dart';

import 'screens/landing_home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/pitch_highway_screen.dart';
import 'screens/piano_pitch_screen.dart';
import 'screens/progress_home_screen.dart';
import 'screens/find_range_lowest_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/subscription_features_screen.dart';
import 'screens/exercise_categories_screen.dart';
import 'theme/app_theme.dart';

class CrescendoApp extends StatefulWidget {
  const CrescendoApp({super.key});

  @override
  State<CrescendoApp> createState() => _CrescendoAppState();
}

class _CrescendoAppState extends State<CrescendoApp> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemeController.mode,
      builder: (context, mode, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: AppThemeController.magicalMode,
          builder: (context, magical, __) {
            final theme = magical ? AppTheme.magical() : AppTheme.light();
            final darkTheme = magical ? AppTheme.magical() : AppTheme.dark();
            final resolvedMode = magical ? ThemeMode.dark : mode;
            return MaterialApp(
              title: 'Crescendo Mobile',
              theme: theme,
              darkTheme: darkTheme,
              themeMode: resolvedMode,
              routes: {
                '/': (_) => const LandingHomeScreen(),
                '/settings': (_) => const SettingsScreen(),
                '/library': (_) => const ExerciseCategoriesScreen(),
                '/piano': (_) => const PianoPitchScreen(),
                '/progress': (_) => const ProgressHomeScreen(),
                '/settings/find_range': (_) => const FindRangeLowestScreen(),
                '/settings/subscription': (_) => const SubscriptionScreen(),
                '/settings/subscription_features': (_) =>
                    const SubscriptionFeaturesScreen(),
              },
            );
          },
        );
      },
    );
  }
}
