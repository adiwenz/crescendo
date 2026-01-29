import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_mobile/core/locator.dart';
import 'package:crescendo_mobile/core/interfaces/i_clock.dart';
import '../fakes/fake_clock.dart';

void main() {
  test('Sanity check: Locator can register fake', () {
    final fakeClock = FakeClock();
    setupTestLocator(clock: fakeClock);
    
    expect(locator<IClock>(), isA<FakeClock>());
    expect(locator<IClock>().now(), fakeClock.now());
  });
}
