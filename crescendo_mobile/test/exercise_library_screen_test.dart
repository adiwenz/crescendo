import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crescendo_mobile/ui/screens/exercise_categories_screen.dart';

void main() {
  testWidgets('Exercise categories flow to info screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ExerciseCategoriesScreen()));

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
