import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:record/record.dart';

/// Centralized manager for microphone/audio session coordination.
/// 
/// Ensures only one component (Exercise or Piano) uses the microphone at a time.
/// Prevents "microphone already in use" errors and resource conflicts.
class AudioSessionManager {
  static final AudioSessionManager _instance = AudioSessionManager._internal();
  factory AudioSessionManager() => _instance;
  AudioSessionManager._internal();

  final AudioRecorder _permissionChecker = AudioRecorder(); // Only for permission checks
  String? _currentOwner; // 'piano' or 'exercise' or null
  bool _isActive = false;
  DateTime? _lastReleaseTime;

  /// Get the singleton instance.
  static AudioSessionManager get instance => _instance;

  /// Check if microphone is currently in use.
  bool get isInUse => _isActive && _currentOwner != null;

  /// Get the current owner of the microphone.
  String? get currentOwner => _currentOwner;

  /// Request microphone access for a specific owner.
  /// 
  /// [owner] - 'piano' or 'exercise'
  /// Returns true if access was granted, false if denied or already in use by another owner.
  Future<bool> requestAccess(String owner) async {
    debugPrint('[AudioSessionManager] Requesting access for: $owner');
    
    if (_currentOwner != null && _currentOwner != owner) {
      debugPrint('[AudioSessionManager] Microphone already in use by: $_currentOwner');
      return false;
    }

    if (_isActive && _currentOwner == owner) {
      debugPrint('[AudioSessionManager] Already active for: $owner');
      return true;
    }

    // If there was a recent release, wait a bit to ensure cleanup
    if (_lastReleaseTime != null) {
      final timeSinceRelease = DateTime.now().difference(_lastReleaseTime!);
      if (timeSinceRelease.inMilliseconds < 200) {
        debugPrint('[AudioSessionManager] Waiting for cleanup...');
        await Future.delayed(Duration(milliseconds: 200 - timeSinceRelease.inMilliseconds));
      }
    }

    // Check permission
    if (!await _permissionChecker.hasPermission()) {
      debugPrint('[AudioSessionManager] Microphone permission denied');
      return false;
    }

    _currentOwner = owner;
    _isActive = true;
    debugPrint('[AudioSessionManager] Access granted to: $owner');
    return true;
  }

  /// Release microphone access for a specific owner.
  /// 
  /// [owner] - 'piano' or 'exercise'
  /// [force] - If true, release even if owner doesn't match (for cleanup)
  Future<void> releaseAccess(String owner, {bool force = false}) async {
    debugPrint('[AudioSessionManager] Releasing access for: $owner (force: $force)');
    
    if (!force && _currentOwner != owner) {
      debugPrint('[AudioSessionManager] Cannot release: current owner is $_currentOwner, not $owner');
      return;
    }

    _currentOwner = null;
    _isActive = false;
    _lastReleaseTime = DateTime.now();
    debugPrint('[AudioSessionManager] Access released for: $owner');
  }

  /// Force release all microphone access (for cleanup/error recovery).
  Future<void> forceReleaseAll() async {
    debugPrint('[AudioSessionManager] Force releasing all access');
    _currentOwner = null;
    _isActive = false;
    _lastReleaseTime = DateTime.now();
  }

  /// Check if microphone permission is granted.
  Future<bool> hasPermission() async {
    return await _permissionChecker.hasPermission();
  }
}
