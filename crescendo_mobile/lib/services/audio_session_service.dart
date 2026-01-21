import 'dart:io' show Platform;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Audio session configuration service
/// Uses audio_session package for iOS audio session management
class AudioSessionService {
  static AudioSession? _session;
  
  /// Get or create audio session instance
  static Future<AudioSession> _getSession() async {
    _session ??= await AudioSession.instance;
    return _session!;
  }
  
  /// Apply audio session configuration for exercise mode (needs mic)
  static Future<void> applyExerciseSession({String tag = 'exercise'}) async {
    if (!Platform.isIOS) return;
    
    try {
      final session = await _getSession();
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.mixWithOthers |
              AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
        ),
      );
      
      if (kDebugMode) {
        debugPrint('[AudioSessionService] [$tag] Applied exercise session (playAndRecord)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioSessionService] [$tag] ERROR applying exercise session: $e');
      }
    }
  }
  
  /// Apply audio session configuration for review mode (no mic)
  static Future<void> applyReviewSession({String tag = 'review'}) async {
    if (!Platform.isIOS) return;
    
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
      
      if (kDebugMode) {
        debugPrint('[AudioSessionService] [$tag] Applied review session (playback)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioSessionService] [$tag] ERROR applying review session: $e');
      }
    }
  }
}
