import 'package:crescendo_mobile/screens/timestamp_sync_test_screen.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: TimestampSyncTestScreen(),
  ));
}
