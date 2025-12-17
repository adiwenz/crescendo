import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crescendo_mobile/ui/screens/exercise_library_screen.dart';

void main() {
  testWidgets('ExerciseLibraryScreen shows categories and opens details',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: ExerciseLibraryScreen()));

    expect(find.text('Exercise Library'), findsOneWidget);
    expect(find.text('Breathing & Support'), findsOneWidget);

    await tester.tap(find.text('Breathing & Support'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Appoggio Breathing'));
    await tester.pumpAndSettle();

    expect(find.text('How to do it'), findsOneWidget);
    expect(find.text('Appoggio Breathing'), findsWidgets);
  });
}
