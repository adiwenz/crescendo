import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/services.dart';

/// Service for encoding PCM audio to AAC (M4A) format
/// Uses platform channels to call native encoders (iOS AVAudioFile, Android MediaCodec)
class AacEncoderService {
  static const MethodChannel _channel = MethodChannel('com.adriannawenz.crescendo/aacEncoder');
  
  /// Encode PCM audio samples to AAC M4A file
  /// 
  /// [pcmSamples] - 16-bit PCM samples (Int16List)
  /// [sampleRate] - Sample rate in Hz (must be 48000)
  /// [outputPath] - Path to output M4A file
  /// [bitrate] - AAC bitrate in kbps (128-160, default 128)
  /// 
  /// Returns the duration of the encoded file in milliseconds
  static Future<int> encodeToM4A({
    required List<int> pcmSamples,
    required int sampleRate,
    required String outputPath,
    int bitrate = 128,
  }) async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      throw UnsupportedError('AAC encoding is only supported on iOS and Android');
    }
    
    if (sampleRate != 48000) {
      throw ArgumentError('Sample rate must be 48000 Hz, got $sampleRate');
    }
    
    if (bitrate < 128 || bitrate > 160) {
      throw ArgumentError('Bitrate must be between 128 and 160 kbps, got $bitrate');
    }
    
    try {
      if (kDebugMode) {
        debugPrint('[AacEncoder] Encoding ${pcmSamples.length} samples to M4A: $outputPath (bitrate=${bitrate}kbps)');
        debugPrint('[AacEncoder] Sample data size: ${pcmSamples.length * 2} bytes');
      }
      
      // Check if sample list is too large for method channel (limit to ~10MB)
      const maxSamplesForChannel = 5 * 1024 * 1024; // 5MB of samples
      if (pcmSamples.length > maxSamplesForChannel) {
        if (kDebugMode) {
          debugPrint('[AacEncoder] Sample list too large (${pcmSamples.length} samples), writing to temp file first...');
        }
        // Write PCM to temp file and pass file path instead
        final tempDir = Directory.systemTemp;
        final tempFile = File('${tempDir.path}/pcm_${DateTime.now().millisecondsSinceEpoch}.raw');
        final bytes = Uint8List(pcmSamples.length * 2);
        final byteData = ByteData.sublistView(bytes);
        for (var i = 0; i < pcmSamples.length; i++) {
          byteData.setInt16(i * 2, pcmSamples[i], Endian.little);
        }
        await tempFile.writeAsBytes(bytes);
        
        final result = await _channel.invokeMethod<int>('encodeToM4AFromFile', {
          'pcmFilePath': tempFile.path,
          'sampleRate': sampleRate,
          'outputPath': outputPath,
          'bitrate': bitrate,
        });
        
        // Clean up temp file
        await tempFile.delete();
        
        final durationMs = result ?? 0;
        
        if (kDebugMode) {
          debugPrint('[AacEncoder] Encoded M4A file from temp PCM: $outputPath (duration=${durationMs}ms)');
        }
        
        return durationMs;
      } else {
        // Small enough to pass directly
        final result = await _channel.invokeMethod<int>('encodeToM4A', {
          'pcmSamples': pcmSamples,
          'sampleRate': sampleRate,
          'outputPath': outputPath,
          'bitrate': bitrate,
        });
        
        final durationMs = result ?? 0;
        
        if (kDebugMode) {
          debugPrint('[AacEncoder] Encoded M4A file: $outputPath (duration=${durationMs}ms)');
        }
        
        return durationMs;
      }
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[AacEncoder] ERROR encoding to M4A: ${e.message}');
        debugPrint('[AacEncoder] Error code: ${e.code}, details: ${e.details}');
      }
      rethrow;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[AacEncoder] ERROR (non-platform): $e');
        debugPrint('[AacEncoder] Stack trace: $stackTrace');
      }
      rethrow;
    }
  }
}
