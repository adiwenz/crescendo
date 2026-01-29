import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:crescendo_mobile/services/reference_audio_cache.dart';
import 'package:crescendo_mobile/models/reference_note.dart';

void main() {
  group('ReferenceAudioCache', () {
    late ReferenceAudioCache cache;
    late Directory tempDir;

    setUp(() async {
      cache = ReferenceAudioCache.instance;
      cache.clear(); // Clear cache before each test
      
      // Create temp directory for test files
      tempDir = await Directory.systemTemp.createTemp('reference_audio_cache_test');
    });

    tearDown(() async {
      // Clean up temp files
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<String> createTempFile(String name) async {
      final file = File('${tempDir.path}/$name');
      await file.writeAsString('test audio data');
      return file.path;
    }

    test('getCached returns null for non-existent entry', () {
      final result = cache.getCached(
        exerciseId: 'test',
        difficulty: 'easy',
        notes: [ReferenceNote(startSec: 0, endSec: 1, midi: 60)],
        sampleRate: 44100,
      );
      expect(result, isNull);
    });

    test('putCached and getCached work correctly', () async {
      final path = await createTempFile('test.wav');
      final notes = [ReferenceNote(startSec: 0, endSec: 1, midi: 60)];

      cache.putCached(
        exerciseId: 'test',
        difficulty: 'easy',
        notes: notes,
        sampleRate: 44100,
        audioPath: path,
      );

      final result = cache.getCached(
        exerciseId: 'test',
        difficulty: 'easy',
        notes: notes,
        sampleRate: 44100,
      );

      expect(result, equals(path));
    });

    test('cache key is deterministic for same parameters', () async {
      final path1 = await createTempFile('path1.wav');
      final path2 = await createTempFile('path2.wav');
      final notes = [ReferenceNote(startSec: 0, endSec: 1, midi: 60)];

      // Put with same parameters twice
      cache.putCached(
        exerciseId: 'test',
        difficulty: 'easy',
        notes: notes,
        sampleRate: 44100,
        audioPath: path1,
      );

      cache.putCached(
        exerciseId: 'test',
        difficulty: 'easy',
        notes: notes,
        sampleRate: 44100,
        audioPath: path2,
      );

      // Should get the second path (overwrite)
      final result = cache.getCached(
        exerciseId: 'test',
        difficulty: 'easy',
        notes: notes,
        sampleRate: 44100,
      );

      expect(result, equals(path2));
    });

    test('cache key changes with different exercise ID', () async {
      final path1 = await createTempFile('path1.wav');
      final path2 = await createTempFile('path2.wav');
      final notes = [ReferenceNote(startSec: 0, endSec: 1, midi: 60)];

      cache.putCached(
        exerciseId: 'test1',
        difficulty: 'easy',
        notes: notes,
        sampleRate: 44100,
        audioPath: path1,
      );

      cache.putCached(
        exerciseId: 'test2',
        difficulty: 'easy',
        notes: notes,
        sampleRate: 44100,
        audioPath: path2,
      );

      final result1 = cache.getCached(
        exerciseId: 'test1',
        difficulty: 'easy',
        notes: notes,
        sampleRate: 44100,
      );

      final result2 = cache.getCached(
        exerciseId: 'test2',
        difficulty: 'easy',
        notes: notes,
        sampleRate: 44100,
      );

      expect(result1, equals(path1));
      expect(result2, equals(path2));
    });

    test('cache key changes with different difficulty', () async {
      final path1 = await createTempFile('path1.wav');
      final path2 = await createTempFile('path2.wav');
      final notes = [ReferenceNote(startSec: 0, endSec: 1, midi: 60)];

      cache.putCached(
        exerciseId: 'test',
        difficulty: 'easy',
        notes: notes,
        sampleRate: 44100,
        audioPath: path1,
      );

      cache.putCached(
        exerciseId: 'test',
        difficulty: 'hard',
        notes: notes,
        sampleRate: 44100,
        audioPath: path2,
      );

      final result1 = cache.getCached(
        exerciseId: 'test',
        difficulty: 'easy',
        notes: notes,
        sampleRate: 44100,
      );

      final result2 = cache.getCached(
        exerciseId: 'test',
        difficulty: 'hard',
        notes: notes,
        sampleRate: 44100,
      );

      expect(result1, equals(path1));
      expect(result2, equals(path2));
    });

    test('cache key changes with different notes', () async {
      final path1 = await createTempFile('path1.wav');
      final path2 = await createTempFile('path2.wav');
      final notes1 = [ReferenceNote(startSec: 0, endSec: 1, midi: 60)];
      final notes2 = [ReferenceNote(startSec: 0, endSec: 1, midi: 62)];

      cache.putCached(
        exerciseId: 'test',
        difficulty: 'easy',
        notes: notes1,
        sampleRate: 44100,
        audioPath: path1,
      );

      cache.putCached(
        exerciseId: 'test',
        difficulty: 'easy',
        notes: notes2,
        sampleRate: 44100,
        audioPath: path2,
      );

      final result1 = cache.getCached(
        exerciseId: 'test',
        difficulty: 'easy',
        notes: notes1,
        sampleRate: 44100,
      );

      final result2 = cache.getCached(
        exerciseId: 'test',
        difficulty: 'easy',
        notes: notes2,
        sampleRate: 44100,
      );

      expect(result1, equals(path1));
      expect(result2, equals(path2));
    });

    test('cache key changes with different sample rate', () async {
      final path1 = await createTempFile('path1.wav');
      final path2 = await createTempFile('path2.wav');
      final notes = [ReferenceNote(startSec: 0, endSec: 1, midi: 60)];

      cache.putCached(
        exerciseId: 'test',
        difficulty: 'easy',
        notes: notes,
        sampleRate: 44100,
        audioPath: path1,
      );

      cache.putCached(
        exerciseId: 'test',
        difficulty: 'easy',
        notes: notes,
        sampleRate: 48000,
        audioPath: path2,
      );

      final result1 = cache.getCached(
        exerciseId: 'test',
        difficulty: 'easy',
        notes: notes,
        sampleRate: 44100,
      );

      final result2 = cache.getCached(
        exerciseId: 'test',
        difficulty: 'easy',
        notes: notes,
        sampleRate: 48000,
      );

      expect(result1, equals(path1));
      expect(result2, equals(path2));
    });

    test('clear removes all entries', () async {
      final path1 = await createTempFile('path1.wav');
      final path2 = await createTempFile('path2.wav');
      final notes = [ReferenceNote(startSec: 0, endSec: 1, midi: 60)];

      cache.putCached(
        exerciseId: 'test1',
        difficulty: 'easy',
        notes: notes,
        sampleRate: 44100,
        audioPath: path1,
      );

      cache.putCached(
        exerciseId: 'test2',
        difficulty: 'easy',
        notes: notes,
        sampleRate: 44100,
        audioPath: path2,
      );

      expect(cache.size, equals(2));

      cache.clear();

      expect(cache.size, equals(0));
      expect(
        cache.getCached(
          exerciseId: 'test1',
          difficulty: 'easy',
          notes: notes,
          sampleRate: 44100,
        ),
        isNull,
      );
    });

    test('cache handles many entries', () async {
      final notes = [ReferenceNote(startSec: 0, endSec: 1, midi: 60)];

      // Add 100 entries
      for (var i = 0; i < 100; i++) {
        final path = await createTempFile('path_$i.wav');
        cache.putCached(
          exerciseId: 'test_$i',
          difficulty: 'easy',
          notes: notes,
          sampleRate: 44100,
          audioPath: path,
        );
      }

      expect(cache.size, equals(100));

      // Verify first few entries exist (not all 100 to keep test fast)
      for (var i = 0; i < 10; i++) {
        final result = cache.getCached(
          exerciseId: 'test_$i',
          difficulty: 'easy',
          notes: notes,
          sampleRate: 44100,
        );
        expect(result, isNotNull);
      }
    });

    test('getCached returns null if file was deleted', () async {
      final path = await createTempFile('deleted.wav');
      final notes = [ReferenceNote(startSec: 0, endSec: 1, midi: 60)];

      cache.putCached(
        exerciseId: 'test',
        difficulty: 'easy',
        notes: notes,
        sampleRate: 44100,
        audioPath: path,
      );

      // Verify it's cached
      expect(
        cache.getCached(
          exerciseId: 'test',
          difficulty: 'easy',
          notes: notes,
          sampleRate: 44100,
        ),
        equals(path),
      );

      // Delete the file
      await File(path).delete();

      // Should return null now
      expect(
        cache.getCached(
          exerciseId: 'test',
          difficulty: 'easy',
          notes: notes,
          sampleRate: 44100,
        ),
        isNull,
      );
    });
  });
}
