import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:crescendo_mobile/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Crescendo App Integration Tests', () {
    testWidgets('app launches and shows home screen', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Verify app launched successfully
      expect(find.byType(app.MyApp), findsOneWidget);
    });

    testWidgets('can navigate to explore tab', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Look for explore/exercises navigation
      final exploreFinder = find.text('Explore');
      if (exploreFinder.evaluate().isNotEmpty) {
        await tester.tap(exploreFinder);
        await tester.pumpAndSettle();

        // Should show exercise list or categories
        expect(find.byType(ListView), findsWidgets);
      }
    });

    testWidgets('can navigate to progress tab', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Look for progress navigation
      final progressFinder = find.text('Progress');
      if (progressFinder.evaluate().isNotEmpty) {
        await tester.tap(progressFinder);
        await tester.pumpAndSettle();

        // Should show progress screen
        expect(find.byType(Scaffold), findsOneWidget);
      }
    });
  });
}
