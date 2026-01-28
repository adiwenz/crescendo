import 'package:flutter_test/flutter_test.dart';

/// Helper to pump widget tester until a condition is met.
/// Useful for waiting for async operations to complete.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  Duration interval = const Duration(milliseconds: 100),
}) async {
  final stopwatch = Stopwatch()..start();
  
  while (!condition()) {
    if (stopwatch.elapsed > timeout) {
      throw TimeoutException(
        'Condition not met within $timeout',
        timeout,
      );
    }
    
    await tester.pump(interval);
  }
}

/// Helper to wait for a future with timeout.
Future<T> waitForFuture<T>(
  Future<T> future, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  return future.timeout(
    timeout,
    onTimeout: () {
      throw TimeoutException(
        'Future did not complete within $timeout',
        timeout,
      );
    },
  );
}

/// Helper to flush all microtasks.
/// Ensures all pending async operations complete.
Future<void> flushMicrotasks() async {
  await Future.delayed(Duration.zero);
}

/// Helper to pump and settle with a timeout.
Future<void> pumpAndSettleWithTimeout(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  await tester.pumpAndSettle(timeout);
}
