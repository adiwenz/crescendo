import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_mobile/services/reference_audio_cache.dart';

void main() {
  group('ReferenceAudioCache', () {
    late ReferenceAudioCache cache;

    setUp(() {
      cache = ReferenceAudioCache();
    });

    test('cache key generation is deterministic', () {
      final key1 = cache.getCacheKey(
        exerciseId: 'ex1',
        rangeHash: 'range123',
        patternHash: 'pattern456',
        difficulty: 'easy',
      );

      final key2 = cache.getCacheKey(
        exerciseId: 'ex1',
        rangeHash: 'range123',
        patternHash: 'pattern456',
        difficulty: 'easy',
      );

      expect(key1, equals(key2));
    });

    test('cache key changes with different parameters', () {
      final key1 = cache.getCacheKey(
        exerciseId: 'ex1',
        rangeHash: 'range123',
        patternHash: 'pattern456',
        difficulty: 'easy',
      );

      final key2 = cache.getCacheKey(
        exerciseId: 'ex1',
        rangeHash: 'range123',
        patternHash: 'pattern456',
        difficulty: 'medium', // Different difficulty
      );

      expect(key1, isNot(equals(key2)));
    });

    test('get returns null for non-existent key', () {
      final result = cache.get('non_existent_key');
      expect(result, isNull);
    });

    test('put and get work correctly', () {
      const key = 'test_key';
      const path = '/test/path.wav';

      cache.put(key, path);
      final result = cache.get(key);

      expect(result, equals(path));
    });

    test('clear removes all entries', () {
      cache.put('key1', '/path1.wav');
      cache.put('key2', '/path2.wav');
      cache.put('key3', '/path3.wav');

      expect(cache.get('key1'), isNotNull);
      expect(cache.get('key2'), isNotNull);
      expect(cache.get('key3'), isNotNull);

      cache.clear();

      expect(cache.get('key1'), isNull);
      expect(cache.get('key2'), isNull);
      expect(cache.get('key3'), isNull);
    });

    test('overwriting existing key updates value', () {
      const key = 'test_key';
      const path1 = '/path1.wav';
      const path2 = '/path2.wav';

      cache.put(key, path1);
      expect(cache.get(key), equals(path1));

      cache.put(key, path2);
      expect(cache.get(key), equals(path2));
    });

    test('cache handles many entries', () {
      // Add 100 entries
      for (var i = 0; i < 100; i++) {
        cache.put('key_$i', '/path_$i.wav');
      }

      // Verify all entries exist
      for (var i = 0; i < 100; i++) {
        expect(cache.get('key_$i'), equals('/path_$i.wav'));
      }
    });

    test('cache key includes all parameters', () {
      final key1 = cache.getCacheKey(
        exerciseId: 'ex1',
        rangeHash: 'range1',
        patternHash: 'pattern1',
        difficulty: 'easy',
      );

      final key2 = cache.getCacheKey(
        exerciseId: 'ex2', // Different exercise
        rangeHash: 'range1',
        patternHash: 'pattern1',
        difficulty: 'easy',
      );

      final key3 = cache.getCacheKey(
        exerciseId: 'ex1',
        rangeHash: 'range2', // Different range
        patternHash: 'pattern1',
        difficulty: 'easy',
      );

      final key4 = cache.getCacheKey(
        exerciseId: 'ex1',
        rangeHash: 'range1',
        patternHash: 'pattern2', // Different pattern
        difficulty: 'easy',
      );

      // All keys should be different
      expect(key1, isNot(equals(key2)));
      expect(key1, isNot(equals(key3)));
      expect(key1, isNot(equals(key4)));
      expect(key2, isNot(equals(key3)));
      expect(key2, isNot(equals(key4)));
      expect(key3, isNot(equals(key4)));
    });
  });
}
