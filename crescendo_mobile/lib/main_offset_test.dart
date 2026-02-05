import 'package:flutter/material.dart';
import 'package:crescendo_mobile/core/locator.dart'; // Ensure registration
import 'package:crescendo_mobile/services/audio_session_service.dart';
import 'package:crescendo_mobile/screens/debug/pitch_highway_replay_offset_test_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Register dependencies (AudioSession etc)
  setupLocator(); 
  
  // Init session
  await AudioSessionService.init();
  
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: PitchHighwayReplayOffsetTestScreen(),
  ));
}
