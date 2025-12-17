import 'package:flutter/material.dart';

import 'screens/history_screen.dart';
import 'screens/piano_pitch_screen.dart';
import 'screens/pitch_highway_screen.dart';
import 'screens/progress_home_screen.dart';
import 'screens/exercise_categories_screen.dart';
import 'screens/hold_exercise_screen.dart';

class CrescendoApp extends StatefulWidget {
  const CrescendoApp({super.key});

  @override
  State<CrescendoApp> createState() => _CrescendoAppState();
}

class _CrescendoAppState extends State<CrescendoApp> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crescendo Mobile',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: IndexedStack(
          index: _index,
          children: const [
            HistoryScreen(),
            PitchHighwayScreen(),
            PianoPitchScreen(),
            ExerciseCategoriesScreen(),
            HoldExerciseScreen(),
            ProgressHomeScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.history), label: 'History'),
            NavigationDestination(icon: Icon(Icons.multiline_chart), label: 'Pitch'),
            NavigationDestination(icon: Icon(Icons.piano), label: 'Piano'),
            NavigationDestination(icon: Icon(Icons.school), label: 'Library'),
            NavigationDestination(icon: Icon(Icons.stop_circle), label: 'Hold'),
            NavigationDestination(icon: Icon(Icons.auto_graph), label: 'Progress'),
          ],
        ),
      ),
    );
  }
}
