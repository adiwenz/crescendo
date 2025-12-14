import 'package:flutter/material.dart';

import 'screens/history_screen.dart';
import 'screens/record_screen.dart';
import 'screens/realtime_pitch_screen.dart';
import 'screens/warmups_screen.dart';

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
            WarmupsScreen(),
            RecordScreen(),
            HistoryScreen(),
            RealtimePitchScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.library_music), label: 'Warmups'),
            NavigationDestination(icon: Icon(Icons.mic), label: 'Record'),
            NavigationDestination(icon: Icon(Icons.history), label: 'History'),
            NavigationDestination(icon: Icon(Icons.graphic_eq), label: 'Realtime'),
          ],
        ),
      ),
    );
  }
}
