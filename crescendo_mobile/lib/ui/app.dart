import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import 'screens/settings_screen.dart';
import 'screens/piano_pitch_screen.dart';
import 'screens/progress_home_screen.dart';
import 'screens/find_range_lowest_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/subscription_features_screen.dart';
import 'screens/exercise_categories_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/explore/explore_screen.dart';
import '../screens/profile/profile_screen.dart';
import 'theme/app_theme.dart';
import 'route_observer.dart';
import 'widgets/app_background.dart';

class CrescendoApp extends StatefulWidget {
  const CrescendoApp({super.key});

  @override
  State<CrescendoApp> createState() => _CrescendoAppState();
}

class _CrescendoAppState extends State<CrescendoApp> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Frame jank detection
    WidgetsBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
      for (final timing in timings) {
        final duration = timing.totalSpan.inMilliseconds;
        if (duration > 33) {
          debugPrint('[JANK] SEVERE: ${duration}ms (build: ${timing.buildDuration.inMilliseconds}ms, raster: ${timing.rasterDuration.inMilliseconds}ms)');
        } else if (duration > 16) {
          debugPrint('[JANK] SLOW: ${duration}ms (build: ${timing.buildDuration.inMilliseconds}ms, raster: ${timing.rasterDuration.inMilliseconds}ms)');
        }
      }
    });
  }

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
            // Get Manrope font family for Cupertino
            final manropeFontFamily = theme.textTheme.bodyMedium?.fontFamily;
            return MaterialApp(
              title: 'Crescendo Mobile',
              theme: theme,
              darkTheme: darkTheme,
              themeMode: resolvedMode,
              // Set Cupertino theme to use Manrope
              builder: (context, child) {
                return CupertinoTheme(
                  data: CupertinoThemeData(
                    textTheme: CupertinoTextThemeData(
                      textStyle: TextStyle(fontFamily: manropeFontFamily),
                      navTitleTextStyle: TextStyle(
                        fontFamily: manropeFontFamily,
                        fontWeight: FontWeight.w600,
                      ),
                      navLargeTitleTextStyle: TextStyle(
                        fontFamily: manropeFontFamily,
                        fontWeight: FontWeight.w700,
                      ),
                      tabLabelTextStyle: TextStyle(
                        fontFamily: manropeFontFamily,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  child: child!,
                );
              },
              navigatorObservers: [routeObserver],
              routes: {
                '/': (_) => _RootScaffold(currentIndex: _index, onTab: (i) => setState(() => _index = i)),
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

class _RootScaffold extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTab;

  const _RootScaffold({required this.currentIndex, required this.onTab});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manropeFontFamily = theme.textTheme.bodyMedium?.fontFamily;
    return Scaffold(
      body: AppBackground(
        child: IndexedStack(
          index: currentIndex,
          children: [
            const HomeScreen(),
            const ExploreScreen(),
            currentIndex == 2 ? const PianoPitchScreen() : const SizedBox.shrink(),
            const ProgressHomeScreen(),
            const ProfileScreen(),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppThemeColors.light.surfaceGlass,
          border: Border(
            top: BorderSide(
              color: AppThemeColors.light.borderGlass,
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          type: BottomNavigationBarType.fixed,
          onTap: onTab,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: AppThemeColors.light.accentPurple,
          unselectedItemColor: AppThemeColors.light.iconMuted,
          selectedLabelStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontFamily: manropeFontFamily,
          ),
          unselectedLabelStyle: TextStyle(
            fontFamily: manropeFontFamily,
          ),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.explore_outlined), label: 'Explore'),
            BottomNavigationBarItem(icon: Icon(Icons.piano), label: 'Piano'),
            BottomNavigationBarItem(icon: Icon(Icons.insights_outlined), label: 'Progress'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
