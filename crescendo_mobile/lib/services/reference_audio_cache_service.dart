import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/reference_note.dart';
import '../models/pitch_highway_difficulty.dart';
import '../services/storage/db.dart';
import 'reference_audio_generator.dart';
import 'exercise_repository.dart';
import 'transposed_exercise_builder.dart';
import '../utils/audio_constants.dart';

/// Service for caching reference audio files for exercises
/// Generates audio files when vocal range changes and stores them in DB + filesystem
class ReferenceAudioCacheService {
  static final ReferenceAudioCacheService instance = ReferenceAudioCacheService._();
  ReferenceAudioCacheService._();
  
  static const int cacheVersion = 2; // Bumped to 2 for AAC M4A format (was 1 for WAV)
  static const int maxCacheSizeBytes = 200 * 1024 * 1024; // 200MB
  static const int defaultSampleRate = ReferenceAudioGenerator.defaultSampleRate;
  
  final AppDatabase _db = AppDatabase();
  final ReferenceAudioGenerator _generator = ReferenceAudioGenerator();
  final ExerciseRepository _exerciseRepo = ExerciseRepository();
  
  /// Generate range hash from vocal range parameters
  static String generateRangeHash({
    required int lowestMidi,
    required int highestMidi,
    String appVersion = '1.0.0',
    int generatorVersion = cacheVersion,
  }) {
    final keyString = '$lowestMidi|$highestMidi|$appVersion|$generatorVersion';
    final bytes = utf8.encode(keyString);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16); // Use first 16 chars
  }
  
  /// Get cache directory for reference audio files
  static Future<Directory> getCacheDirectory() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(p.join(documentsDir.path, 'reference_audio'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }
  
  /// Get cached audio file path for an exercise
  /// Returns null if not cached
  Future<String?> getCachedAudioPath({
    required String exerciseId,
    required String rangeHash,
    required String variantKey,
  }) async {
    if (kDebugMode) {
      debugPrint('[ReferenceAudioCache] Looking up cache: exerciseId=$exerciseId, rangeHash=$rangeHash, variantKey=$variantKey');
    }
    
    final db = await _db.database;
    final rows = await db.query(
      'reference_audio_cache',
      where: 'exerciseId = ? AND rangeHash = ? AND variantKey = ?',
      whereArgs: [exerciseId, rangeHash, variantKey],
      limit: 1,
    );
    
    if (rows.isEmpty) {
      if (kDebugMode) {
        // Debug: check what's actually in the DB for this exercise
        final allRows = await db.query(
          'reference_audio_cache',
          where: 'exerciseId = ?',
          whereArgs: [exerciseId],
        );
        if (allRows.isNotEmpty) {
          debugPrint('[ReferenceAudioCache] Found ${allRows.length} entries for $exerciseId, but none match rangeHash=$rangeHash, variantKey=$variantKey');
          for (final row in allRows) {
            debugPrint('[ReferenceAudioCache]   - rangeHash=${row['rangeHash']}, variantKey=${row['variantKey']}, filePath=${row['filePath']}');
          }
        } else {
          debugPrint('[ReferenceAudioCache] No cache entries found for exerciseId=$exerciseId');
        }
      }
      return null;
    }
    
    final filePath = rows.first['filePath'] as String;
    final file = File(filePath);
    
    if (await file.exists()) {
      if (kDebugMode) {
        debugPrint('[ReferenceAudioCache] Found cached file: $filePath');
      }
      return filePath;
    } else {
      if (kDebugMode) {
        debugPrint('[ReferenceAudioCache] File missing from disk: $filePath (removing from DB)');
      }
      // File missing, remove from DB
      await db.delete(
        'reference_audio_cache',
        where: 'id = ?',
        whereArgs: [rows.first['id']],
      );
      return null;
    }
  }
  
  /// Generate and cache audio for all exercises
  /// Shows progress via callback: (current, total, exerciseId)
  Future<void> generateCacheForRange({
    required int lowestMidi,
    required int highestMidi,
    void Function(int current, int total, String exerciseId)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final rangeHash = generateRangeHash(
      lowestMidi: lowestMidi,
      highestMidi: highestMidi,
    );
    
    if (kDebugMode) {
      debugPrint('[ReferenceAudioCache] Generating cache for range: $lowestMidi-$highestMidi (hash=$rangeHash)');
    }
    
    final exercises = _exerciseRepo.getExercises();
    final exercisesToCache = exercises.where((e) {
      // Only cache exercises with highwaySpec (pitch highway exercises)
      // Skip glide exercises (they may use procedural audio)
      return e.highwaySpec != null && 
             e.highwaySpec!.segments.isNotEmpty &&
             e.id != 'sirens'; // Sirens handled separately if needed
    }).toList();
    
    if (kDebugMode) {
      debugPrint('[ReferenceAudioCache] Found ${exercisesToCache.length} exercises to cache: ${exercisesToCache.map((e) => e.id).join(", ")}');
    }
    
    int current = 0;
    final total = exercisesToCache.length * PitchHighwayDifficulty.values.length;
    
    for (final exercise in exercisesToCache) {
      if (shouldCancel?.call() == true) {
        if (kDebugMode) {
          debugPrint('[ReferenceAudioCache] Cache generation cancelled');
        }
        break;
      }
      
      // Generate for each difficulty
      for (final difficulty in PitchHighwayDifficulty.values) {
        current++;
        onProgress?.call(current, total, exercise.id);
        
        final variantKey = difficulty.name;
        
        if (kDebugMode) {
          debugPrint('[ReferenceAudioCache] Generating: ${exercise.id}/$variantKey ($current/$total)');
        }
        
        try {
          final notes = TransposedExerciseBuilder.buildTransposedSequence(
            exercise: exercise,
            lowestMidi: lowestMidi,
            highestMidi: highestMidi,
            leadInSec: AudioConstants.leadInSec,
            difficulty: difficulty,
          );
          
          if (kDebugMode) {
            debugPrint('[ReferenceAudioCache] Built ${notes.length} notes for ${exercise.id}/$variantKey');
          }
          
          await _generateAndCacheAudio(
            exerciseId: exercise.id,
            rangeHash: rangeHash,
            variantKey: variantKey,
            notes: notes,
          );
        } catch (e, stackTrace) {
          if (kDebugMode) {
            debugPrint('[ReferenceAudioCache] ERROR generating ${exercise.id}/$variantKey: $e');
            debugPrint('[ReferenceAudioCache] Stack trace: $stackTrace');
          }
          // Continue with next exercise even if one fails
        }
        
        // Yield to allow UI updates between generations
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }
    
    // Clean up old cache entries (LRU eviction)
    await _evictOldCache();
    
    if (kDebugMode) {
      // Debug: List all cached exercises after generation
      final db = await _db.database;
      final allEntries = await db.query('reference_audio_cache');
      final exerciseIds = allEntries.map((e) => e['exerciseId'] as String).toSet();
      debugPrint('[ReferenceAudioCache] Cache generation complete. Cached exercises: ${exerciseIds.join(", ")}');
      debugPrint('[ReferenceAudioCache] Total cache entries: ${allEntries.length}');
      
      // Check specifically for head_voice_scales
      final headVoiceEntries = allEntries.where((e) => e['exerciseId'] == 'head_voice_scales').toList();
      if (headVoiceEntries.isEmpty) {
        debugPrint('[ReferenceAudioCache] WARNING: head_voice_scales not found in cache after generation!');
      } else {
        debugPrint('[ReferenceAudioCache] Found ${headVoiceEntries.length} entries for head_voice_scales:');
        for (final entry in headVoiceEntries) {
          debugPrint('[ReferenceAudioCache]   - rangeHash=${entry['rangeHash']}, variantKey=${entry['variantKey']}, filePath=${entry['filePath']}');
        }
      }
    }
  }
  
  /// Generate and cache audio for a single exercise variant
  Future<void> _generateAndCacheAudio({
    required String exerciseId,
    required String rangeHash,
    required String variantKey,
    required List<ReferenceNote> notes,
  }) async {
    try {
      // Check if already cached
      final existing = await getCachedAudioPath(
        exerciseId: exerciseId,
        rangeHash: rangeHash,
        variantKey: variantKey,
      );
      if (existing != null) {
        if (kDebugMode) {
          debugPrint('[ReferenceAudioCache] Already cached: $exerciseId/$variantKey');
        }
        return;
      }
      
      // Generate audio file
      final cacheDir = await getCacheDirectory();
      final rangeDir = Directory(p.join(cacheDir.path, rangeHash));
      if (!await rangeDir.exists()) {
        await rangeDir.create(recursive: true);
      }
      
      final fileName = '${exerciseId}_$variantKey.m4a';
      final filePath = p.join(rangeDir.path, fileName);
      
      if (kDebugMode) {
        debugPrint('[ReferenceAudioCache] Generating audio for $exerciseId/$variantKey (${notes.length} notes)...');
      }
      
      final result = await _generator.generateAudio(
        notes: notes,
        sampleRate: defaultSampleRate,
        outputPath: filePath,
      );
      
      // Verify file was created
      if (!await result.file.exists()) {
        if (kDebugMode) {
          debugPrint('[ReferenceAudioCache] ERROR: Generated file does not exist: ${result.file.path}');
        }
        throw Exception('Generated audio file does not exist: ${result.file.path}');
      }
      
      // Store in database
      final db = await _db.database;
      await db.insert(
        'reference_audio_cache',
        {
          'exerciseId': exerciseId,
          'rangeHash': rangeHash,
          'variantKey': variantKey,
          'filePath': result.file.path,
          'durationMs': result.durationMs,
          'sampleRate': defaultSampleRate,
          'codec': 'aac',
          'generatedAt': DateTime.now().millisecondsSinceEpoch,
          'version': cacheVersion,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      if (kDebugMode) {
        final fileSize = await result.file.length();
        debugPrint('[ReferenceAudioCache] ✅ Cached: $exerciseId/$variantKey -> ${result.file.path} (${fileSize} bytes, ${result.durationMs}ms)');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[ReferenceAudioCache] ❌ ERROR generating audio for $exerciseId/$variantKey: $e');
        debugPrint('[ReferenceAudioCache] Stack trace: $stackTrace');
      }
      // Don't rethrow - continue with other exercises even if one fails
    }
  }
  
  /// Evict old cache entries if cache size exceeds limit (LRU)
  Future<void> _evictOldCache() async {
    try {
      final db = await _db.database;
      
      // Get all cache entries sorted by generatedAt (oldest first)
      final entries = await db.query(
        'reference_audio_cache',
        orderBy: 'generatedAt ASC',
      );
      
      // Calculate total cache size
      int totalSize = 0;
      final entrySizes = <int, int>{}; // id -> size
      
      for (final entry in entries) {
        final filePath = entry['filePath'] as String;
        final file = File(filePath);
        if (await file.exists()) {
          final size = await file.length();
          totalSize += size;
          entrySizes[entry['id'] as int] = size;
        }
      }
      
      // If over limit, delete oldest entries
      if (totalSize > maxCacheSizeBytes) {
        if (kDebugMode) {
          debugPrint('[ReferenceAudioCache] Cache size ${totalSize ~/ 1024 ~/ 1024}MB exceeds limit, evicting...');
        }
        
        int sizeToFree = totalSize - maxCacheSizeBytes;
        for (final entry in entries) {
          if (sizeToFree <= 0) break;
          
          final id = entry['id'] as int;
          final size = entrySizes[id] ?? 0;
          final filePath = entry['filePath'] as String;
          
          // Delete file
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
          }
          
          // Delete DB entry
          await db.delete(
            'reference_audio_cache',
            where: 'id = ?',
            whereArgs: [id],
          );
          
          sizeToFree -= size;
          
          if (kDebugMode) {
            debugPrint('[ReferenceAudioCache] Evicted: ${entry['exerciseId']}/${entry['variantKey']}');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ReferenceAudioCache] Error evicting cache: $e');
      }
    }
  }
  
  /// Clear all cache entries for a specific range hash
  Future<void> clearCacheForRange(String rangeHash) async {
    final db = await _db.database;
    final entries = await db.query(
      'reference_audio_cache',
      where: 'rangeHash = ?',
      whereArgs: [rangeHash],
    );
    
    for (final entry in entries) {
      final filePath = entry['filePath'] as String;
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    
    await db.delete(
      'reference_audio_cache',
      where: 'rangeHash = ?',
      whereArgs: [rangeHash],
    );
    
    if (kDebugMode) {
      debugPrint('[ReferenceAudioCache] Cleared cache for range: $rangeHash');
    }
  }
  
  /// Invalidate cache when generator version changes
  /// Also removes old WAV files from previous version
  Future<void> invalidateCacheForVersion(int newVersion) async {
    if (newVersion > cacheVersion) {
      final db = await _db.database;
      final entries = await db.query('reference_audio_cache');
      
      // Delete all cached files
      for (final entry in entries) {
        final filePath = entry['filePath'] as String;
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      }
      
      // Also clean up any old WAV files in cache directories
      final cacheDir = await getCacheDirectory();
      if (await cacheDir.exists()) {
        await for (final rangeDir in cacheDir.list()) {
          if (rangeDir is Directory) {
            await for (final file in rangeDir.list()) {
              if (file is File && file.path.endsWith('.wav')) {
                await file.delete();
                if (kDebugMode) {
                  debugPrint('[ReferenceAudioCache] Deleted old WAV file: ${file.path}');
                }
              }
            }
          }
        }
      }
      
      await db.delete('reference_audio_cache');
      
      if (kDebugMode) {
        debugPrint('[ReferenceAudioCache] Invalidated all cache (version change: $cacheVersion -> $newVersion)');
      }
    }
  }
  
  /// Debug: List all cached files for an exercise
  Future<List<Map<String, dynamic>>> debugListCachedFiles(String exerciseId) async {
    final db = await _db.database;
    final rows = await db.query(
      'reference_audio_cache',
      where: 'exerciseId = ?',
      whereArgs: [exerciseId],
    );
    
    final results = <Map<String, dynamic>>[];
    for (final row in rows) {
      final filePath = row['filePath'] as String;
      final file = File(filePath);
      results.add({
        'rangeHash': row['rangeHash'],
        'variantKey': row['variantKey'],
        'filePath': filePath,
        'exists': await file.exists(),
        'size': await file.exists() ? await file.length() : 0,
        'codec': row['codec'],
        'version': row['version'],
      });
    }
    return results;
  }
  
  /// Clean up old WAV files on app startup (backward compatibility)
  Future<void> cleanupOldWavFiles() async {
    try {
      final cacheDir = await getCacheDirectory();
      if (!await cacheDir.exists()) return;
      
      int deletedCount = 0;
      await for (final rangeDir in cacheDir.list()) {
        if (rangeDir is Directory) {
          await for (final file in rangeDir.list()) {
            if (file is File && file.path.endsWith('.wav')) {
              await file.delete();
              deletedCount++;
            }
          }
        }
      }
      
      if (kDebugMode && deletedCount > 0) {
        debugPrint('[ReferenceAudioCache] Cleaned up $deletedCount old WAV files');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ReferenceAudioCache] Error cleaning up old WAV files: $e');
      }
    }
  }
}
