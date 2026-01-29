import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/services.dart';

/// iOS-specific audio session configuration service
/// Ensures MIDI playback works with headphones/Bluetooth
class IOSAudioSessionService {
  static const MethodChannel _channel = MethodChannel('com.adriannawenz.crescendo/audioSession');
  
  /// Ensure audio session is configured for review playback (MIDI + recorded audio)
  /// This must be called before starting MIDI playback, especially with headphones
  /// 
  /// Returns a map with session configuration details (for debugging)
  /// On non-iOS platforms, returns empty map (no-op)
  static Future<Map<String, dynamic>> ensureReviewAudioSession({String tag = 'review'}) async {
    if (!Platform.isIOS) {
      if (kDebugMode) {
        debugPrint('[IOSAudioSessionService] Not iOS, skipping audio session configuration');
      }
      return {};
    }
    
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'ensureReviewAudioSession',
        {'tag': tag},
      );
      
      final configMap = Map<String, dynamic>.from(result ?? {});
      
      if (kDebugMode) {
        final category = configMap['category'] as String? ?? 'unknown';
        final mode = configMap['mode'] as String? ?? 'unknown';
        final hasHeadphones = configMap['hasHeadphones'] as bool? ?? false;
        final outputs = configMap['outputs'] as List? ?? [];
        final sampleRate = configMap['sampleRate'] as double? ?? 0.0;
        
        debugPrint('[IOSAudioSessionService] [$tag] Audio session configured:');
        debugPrint('[IOSAudioSessionService] [$tag]   category=$category, mode=$mode');
        debugPrint('[IOSAudioSessionService] [$tag]   hasHeadphones=$hasHeadphones');
        debugPrint('[IOSAudioSessionService] [$tag]   outputs=${outputs.length}');
        for (var output in outputs) {
          final outputMap = Map<String, dynamic>.from(output as Map);
          final portType = outputMap['portType'] as String? ?? 'unknown';
          final portName = outputMap['portName'] as String? ?? 'unknown';
          debugPrint('[IOSAudioSessionService] [$tag]     - $portType: $portName');
        }
        debugPrint('[IOSAudioSessionService] [$tag]   sampleRate=$sampleRate Hz');
        
        if (hasHeadphones) {
          final bluetoothOutputs = outputs.where((o) {
            final map = Map<String, dynamic>.from(o as Map);
            final portType = map['portType'] as String? ?? '';
            return portType.contains('Bluetooth');
          }).toList();
          if (bluetoothOutputs.isNotEmpty) {
            debugPrint('[IOSAudioSessionService] [$tag] ✓ Bluetooth route detected, allowBluetooth options should be set');
          }
        }
      }
      
      return configMap;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[IOSAudioSessionService] [$tag] ERROR configuring audio session: $e');
      }
      return {'error': e.toString()};
    }
  }
}
