import 'package:crescendo_mobile/audio/ref_audio/ref_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RefSpec Tests', () {
    test('Canonical JSON is sorted and stable', () {
      final spec1 = RefSpec(
        exerciseId: 'scale_major',
        lowMidi: 48,
        highMidi: 60,
        extraOptions: {'b': 2, 'a': 1, 'c': 3},
      );

      final json1 = spec1.toCanonicalJson();
      final extra = json1['extraOptions'] as Map<String, dynamic>;
      
      // Check sorting
      expect(extra.keys.toList(), ['a', 'b', 'c']);
      
      // Check cache key stability
      final spec2 = RefSpec(
        exerciseId: 'scale_major',
        lowMidi: 48,
        highMidi: 60,
        extraOptions: {'c': 3, 'a': 1, 'b': 2}, // Different order
      );
      
      expect(spec1.cacheKey, spec2.cacheKey);
      expect(spec1.filename, spec2.filename);
    });

    test('Different content produces different hash', () {
      final spec1 = RefSpec(
        exerciseId: 'scale_major',
        lowMidi: 48,
        highMidi: 60,
      );
      
      final spec2 = RefSpec(
        exerciseId: 'scale_major',
        lowMidi: 48,
        highMidi: 61, // Changed
      );
      
      expect(spec1.cacheKey, isNot(equals(spec2.cacheKey)));
    });

    test('Filename format is correct', () {
      final spec = RefSpec(
        exerciseId: 'scale_major',
        lowMidi: 48,
        highMidi: 60,
        renderVersion: 'v2',
      );
      
      expect(spec.filename, startsWith('scale_major_48-60_v2_'));
      expect(spec.filename, endsWith('.wav'));
    });
  });
}
