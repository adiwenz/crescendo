import 'dart:async';
import 'dart:io' show Platform;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/services.dart';
import '../../core/locator.dart';
import '../../core/interfaces/i_audio_session.dart';

/// Audio session configuration service
/// Uses audio_session package for iOS audio session management
class AudioSessionService {
  static IAudioSession? _session; // Change type to Interface
  static const MethodChannel _channel = MethodChannel('com.adriannawenz.crescendo/audioSession');
  static StreamSubscription? _interruptionSub;
  static StreamSubscription? _routeChangeSub;

  /// Initialize audio session
  static Future<void> init() async {
    // Just get the session to initialize it
    await _getSession();
  }

  /// Get or create audio session instance
  static Future<IAudioSession> _getSession() async {
    _session ??= locator<IAudioSession>(); // Use locator
    return _session!;
  }
  
  /// Get current audio session state for logging
  static Future<Map<String, dynamic>?> _getSessionState() async {
    if (!Platform.isIOS) return null;
    try {
      // Verify session is accessible (audio_session package doesn't expose category/mode directly)
      await _getSession();
      return {
        'sessionActive': true,
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioSessionService] Error getting session state: $e');
      }
      return null;
    }
  }
  
  /// Override output audio port (iOS only)
  /// [useSpeaker] - If true, force speaker output; if false, use default routing
  static Future<void> overrideOutputPort({required bool useSpeaker, String tag = 'override'}) async {
    if (!Platform.isIOS) return;
    
    try {
      if (kDebugMode) {
        debugPrint('[AudioSessionService] [$tag] Overriding output port: useSpeaker=$useSpeaker');
      }
      
      // Use method channel to call AVAudioSession.overrideOutputAudioPort
      await _channel.invokeMethod('overrideOutputPort', {'useSpeaker': useSpeaker});
      
      if (kDebugMode) {
        debugPrint('[AudioSessionService] [$tag] Output port override complete');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioSessionService] [$tag] ERROR overriding output port: $e');
      }
    }
  }
  
  /// Apply audio session configuration for exercise mode (needs mic)
  /// [overrideToSpeaker] - If true, force speaker output even if headphones are connected
  static Future<void> applyExerciseSession({
    String tag = 'exercise',
    bool overrideToSpeaker = false,
  }) async {
    if (!Platform.isIOS) return;
    
    final beforeState = await _getSessionState();
    if (kDebugMode && beforeState != null) {
      debugPrint('[AudioSessionService] [$tag] BEFORE applyExerciseSession: $beforeState');
    }
    
    try {
      final session = await _getSession();
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.mixWithOthers |
              AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: AVAudioSessionMode.measurement,
        ),
      );
      
      // Override output port if requested
      if (overrideToSpeaker) {
        await overrideOutputPort(useSpeaker: true, tag: tag);
      }
      
      final afterState = await _getSessionState();
      if (kDebugMode) {
        debugPrint('[AudioSessionService] [$tag] Applied exercise session (playAndRecord)');
        if (afterState != null) {
          debugPrint('[AudioSessionService] [$tag] AFTER applyExerciseSession: $afterState');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioSessionService] [$tag] ERROR applying exercise session: $e');
      }
    }
  }
  
  /// Apply audio session configuration for review mode (no mic)
  /// [overrideToSpeaker] - If true, force speaker output even if headphones are connected
  static Future<void> applyReviewSession({
    String tag = 'review',
    bool overrideToSpeaker = false,
  }) async {
    if (!Platform.isIOS) return;
    
    final beforeState = await _getSessionState();
    if (kDebugMode && beforeState != null) {
      debugPrint('[AudioSessionService] [$tag] BEFORE applyReviewSession: $beforeState');
    }
    
    try {
      final session = await _getSession();
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.mixWithOthers |
              AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
        ),
      );
      
      // Override output port if requested
      if (overrideToSpeaker) {
        await overrideOutputPort(useSpeaker: true, tag: tag);
      }
      
      final afterState = await _getSessionState();
      if (kDebugMode) {
        debugPrint('[AudioSessionService] [$tag] Applied review session (playback)');
        if (afterState != null) {
          debugPrint('[AudioSessionService] [$tag] AFTER applyReviewSession: $afterState');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioSessionService] Error applying review session: $e');
      }
    }
  }

  static Future<SyncMetrics?> getSyncMetrics() async {
    if (!Platform.isIOS) return null;
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod('getSyncMetrics');
      if (result == null) return null;
      
      return SyncMetrics(
        inputLatency: result['inputLatency'] as double,
        outputLatency: result['outputLatency'] as double,
        ioBufferDuration: result['ioBufferDuration'] as double,
        isHeadphones: result['isHeadphones'] as bool,
        sampleRate: result['sampleRate'] as double,
        currentHostTime: result['currentHostTime'] as double,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioSessionService] Error getting sync metrics: $e');
      }
      return null;
    }
  }
}

class SyncMetrics {
  final double inputLatency;
  final double outputLatency;
  final double ioBufferDuration;
  final bool isHeadphones;
  final double sampleRate;
  final double currentHostTime;

  SyncMetrics({
    required this.inputLatency,
    required this.outputLatency,
    required this.ioBufferDuration,
    required this.isHeadphones,
    required this.sampleRate,
    required this.currentHostTime,
  });

  @override
  String toString() {
    return 'SyncMetrics(inLat=${(inputLatency * 1000).toStringAsFixed(1)}ms, '
           'outLat=${(outputLatency * 1000).toStringAsFixed(1)}ms, '
           'isHP=$isHeadphones, hostTime=$currentHostTime)';
  }
}
