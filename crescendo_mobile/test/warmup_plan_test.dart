import 'package:flutter_test/flutter_test.dart';

import 'package:crescendo_mobile/models/warmup.dart';

void main() {
  test('warmup builds sequential segments', () {
    final w = WarmupDefinition(
      id: 't',
      name: 'test',
      notes: const ['C4', 'D4'],
      durations: const [0.5, 0.5],
      gap: 0.1,
    );
    final segs = w.buildPlan();
    expect(segs.length, 2);
    expect(segs.first.start, 0);
    expect(segs.first.end, 0.5);
    expect(segs.last.start, closeTo(0.6, 1e-6));
  });
}
