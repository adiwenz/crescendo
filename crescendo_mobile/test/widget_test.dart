import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Displays Crescendo text', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Crescendo')),
        ),
      ),
    );

    expect(find.text('Crescendo'), findsOneWidget);
  });
}
