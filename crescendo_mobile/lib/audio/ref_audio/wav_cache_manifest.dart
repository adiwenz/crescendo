import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ref_spec.dart';

/// Entry in the cache manifest.
class WavCacheEntry {
  final String path;
  final int fileSize;
  final DateTime createdAt;
  DateTime lastUsedAt;
  final Map<String, dynamic> specJson;

  WavCacheEntry({
    required this.path,
    required this.fileSize,
    required this.createdAt,
    required this.lastUsedAt,
    required this.specJson,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'fileSize': fileSize,
        'createdAt': createdAt.toIso8601String(),
        'lastUsedAt': lastUsedAt.toIso8601String(),
        'specJson': specJson,
      };

  factory WavCacheEntry.fromJson(Map<String, dynamic> json) {
    return WavCacheEntry(
      path: json['path'] as String,
      fileSize: json['fileSize'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsedAt: DateTime.parse(json['lastUsedAt'] as String),
      specJson: json['specJson'] as Map<String, dynamic>,
    );
  }
}

/// Manages the persistence of cache metadata.
class WavCacheManifest {
  static const String _manifestFileName = 'manifest_v1.json';
  
  // Logical map: CacheKey -> Entry
  final Map<String, WavCacheEntry> _entries = {};
  
  late Directory _cacheDir;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    final appSupport = await getApplicationSupportDirectory();
    _cacheDir = Directory(p.join(appSupport.path, 'ref_wavs'));
    
    if (!await _cacheDir.exists()) {
      await _cacheDir.create(recursive: true);
    }

    await _loadManifest();
    _initialized = true;
  }

  Directory get cacheDir => _cacheDir;

  WavCacheEntry? get(RefSpec spec) {
    final entry = _entries[spec.cacheKey];
    if (entry != null) {
      // Basic check if file still exists on disk could be done here, 
      // but for performance we might skip traversing disk on every 'get'.
      // We'll rely on periodic cleanup to remove stale entries.
      return entry;
    }
    return null;
  }

  /// Records a new file in the manifest.
  Future<void> put(RefSpec spec, File file) async {
    final stat = await file.stat();
    final entry = WavCacheEntry(
      path: file.path,
      fileSize: stat.size,
      createdAt: DateTime.now(),
      lastUsedAt: DateTime.now(),
      specJson: spec.toCanonicalJson(),
    );
    
    _entries[spec.cacheKey] = entry;
    await _flush();
  }

  /// Updates usage timestamp for LRU.
  Future<void> touch(RefSpec spec) async {
    final entry = _entries[spec.cacheKey];
    if (entry != null) {
      entry.lastUsedAt = DateTime.now();
      await _flush(); // Maybe debounce this if it happens too often during rapid navigation
    }
  }

  /// Removes an entry and deletes the file.
  Future<void> remove(String cacheKey) async {
    final entry = _entries.remove(cacheKey);
    if (entry != null) {
      final file = File(entry.path);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (e) {
          debugPrint('[WavCacheManifest] Failed to delete file: ${entry.path}');
        }
      }
      await _flush();
    }
  }
  
  /// Perform eviction based on maxBytes.
  /// Removes least recently used items until total size is under limit.
  Future<void> evictOldest(int maxBytes) async {
    int totalSize = _entries.values.fold(0, (sum, e) => sum + e.fileSize);
    
    if (totalSize <= maxBytes) return;

    // Sort by lastUsedAt (ascending = oldest first)
    final sortedKeys = _entries.keys.toList()
      ..sort((k1, k2) => _entries[k1]!.lastUsedAt.compareTo(_entries[k2]!.lastUsedAt));

    for (final key in sortedKeys) {
      if (totalSize <= maxBytes) break;
      
      final entry = _entries[key]!;
      await remove(key); // This removes from _entries AND deletes file
      totalSize -= entry.fileSize;
      debugPrint('[WavCacheManifest] Evicted $key (${entry.fileSize} bytes)');
    }
  }

  Future<void> _loadManifest() async {
    final file = File(p.join(_cacheDir.path, _manifestFileName));
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        
        _entries.clear();
        json.forEach((key, value) {
          _entries[key] = WavCacheEntry.fromJson(value);
        });
      } catch (e) {
        debugPrint('[WavCacheManifest] Failed to load manifest: $e');
        // Corrupt manifest? Start fresh.
        _entries.clear();
      }
    }
  }

  Future<void> _flush() async {
    if (!_initialized) return;
    final file = File(p.join(_cacheDir.path, _manifestFileName));
    try {
      final json = _entries.map((k, v) => MapEntry(k, v.toJson()));
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint('[WavCacheManifest] Failed to save manifest: $e');
    }
  }
}
