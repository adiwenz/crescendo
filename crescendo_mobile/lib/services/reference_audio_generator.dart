import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, compute;
import '../models/reference_note.dart';
import 'aac_encoder_service.dart';

/// Generates reference audio files from note schedules
/// Uses simple piano synth (same as ReviewAudioBounceService) for consistency
/// Outputs AAC-LC in M4A container for efficient storage
class ReferenceAudioGenerator {
  static const int defaultSampleRate = 48000;
  static const double fadeInOutMs = 8.0; // 8ms fade in/out per note
  static const int defaultBitrate = 128; // kbps (128-160 range)
  
  /// Generate audio file from reference notes
  /// Returns the generated file and its duration in milliseconds
  /// Output format: AAC-LC in M4A container
  Future<({File file, int durationMs})> generateAudio({
    required List<ReferenceNote> notes,
    required int sampleRate,
    required String outputPath,
    int bitrate = defaultBitrate,
  }) async {
    final startTime = DateTime.now();
    
    if (kDebugMode) {
      debugPrint('[ReferenceAudioGenerator] Generating AAC M4A: ${notes.length} notes, sampleRate=$sampleRate, bitrate=${bitrate}kbps, output=$outputPath');
    }
    
    // Calculate duration from notes
    final durationSec = notes.isEmpty 
        ? 0.0 
        : notes.map((n) => n.endSec).reduce(math.max);
    
    // Generate samples in background isolate to avoid UI freeze
    final noteData = notes.map((n) => <String, dynamic>{
      'startSec': n.startSec,
      'endSec': n.endSec,
      'midi': n.midi,
    }).toList();
    
    final samples = await compute(_generateSamplesInIsolate, <String, dynamic>{
      'notes': noteData,
      'sampleRate': sampleRate,
      'durationSec': durationSec,
    });
    
    // Convert to 16-bit PCM (also in isolate)
    final pcmSamples = await compute(_convertToPcm16, samples);
    
    // Encode to AAC M4A
    int durationMs;
    try {
      durationMs = await AacEncoderService.encodeToM4A(
        pcmSamples: pcmSamples,
        sampleRate: sampleRate,
        outputPath: outputPath,
        bitrate: bitrate,
      );
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[ReferenceAudioGenerator] ERROR encoding to M4A: $e');
        debugPrint('[ReferenceAudioGenerator] Stack trace: $stackTrace');
      }
      rethrow;
    }
    
    // Verify file was created
    final outputFile = File(outputPath);
    if (!await outputFile.exists()) {
      throw Exception('AAC encoding completed but output file does not exist: $outputPath');
    }
    
    final fileSize = await outputFile.length();
    if (fileSize == 0) {
      throw Exception('AAC encoding created empty file: $outputPath');
    }
    
    final elapsed = DateTime.now().difference(startTime);
    
    if (kDebugMode) {
      debugPrint('[ReferenceAudioGenerator] ✅ Generated AAC M4A in ${elapsed.inMilliseconds}ms: $outputPath (${fileSize} bytes, ${durationMs}ms duration)');
    }
    
    return (file: outputFile, durationMs: durationMs);
  }
  
  /// Generate audio samples from reference notes (static for isolate)
  static List<double> _generateSamplesInIsolate(Map<String, dynamic> params) {
    final notesData = params['notes'] as List<dynamic>;
    final sampleRate = params['sampleRate'] as int;
    final durationSec = params['durationSec'] as double;
    
    final totalFrames = (durationSec * sampleRate).ceil();
    final samples = List<double>.filled(totalFrames, 0.0);
    final fadeFrames = ((fadeInOutMs / 1000.0) * sampleRate).round();
    
    for (final noteData in notesData) {
      final startSec = noteData['startSec'] as double;
      final endSec = noteData['endSec'] as double;
      final midi = noteData['midi'] as int;
      
      final startFrame = (startSec * sampleRate).round();
      final endFrame = math.min((endSec * sampleRate).round(), totalFrames);
      final noteFrames = endFrame - startFrame;
      
      if (noteFrames <= 0 || startFrame < 0 || startFrame >= totalFrames) continue;
      
      final hz = 440.0 * math.pow(2.0, (midi - 69.0) / 12.0);
      
      for (var f = 0; f < noteFrames; f++) {
        final frameIndex = startFrame + f;
        if (frameIndex >= totalFrames) break;
        
        final noteTime = f / sampleRate;
        final sample = _pianoSampleStatic(hz, noteTime);
        
        // Apply fade in/out
        double fade = 1.0;
        if (f < fadeFrames) {
          fade = f / fadeFrames; // Fade in
        } else if (f >= noteFrames - fadeFrames) {
          fade = (noteFrames - f) / fadeFrames; // Fade out
        }
        
        samples[frameIndex] += sample * fade;
      }
    }
    
    return samples;
  }
  
  /// Convert samples to PCM16 (static for isolate)
  static List<int> _convertToPcm16(List<double> samples) {
    return samples.map((s) {
      final clamped = s.clamp(-1.0, 1.0);
      return (clamped * 32767.0).round().clamp(-32768, 32767);
    }).toList();
  }
  
  /// Piano sample generator (static for isolate use)
  static double _pianoSampleStatic(double hz, double noteTime) {
    final attack = (noteTime / 0.02).clamp(0.0, 1.0);
    final decay = math.exp(-3.0 * noteTime);
    final env = attack * decay;
    final fundamental = math.sin(2 * math.pi * hz * noteTime);
    final harmonic2 = 0.6 * math.sin(2 * math.pi * hz * 2 * noteTime);
    final harmonic3 = 0.3 * math.sin(2 * math.pi * hz * 3 * noteTime);
    final harmonic4 = 0.15 * math.sin(2 * math.pi * hz * 4 * noteTime);
    return 0.45 * env * (fundamental + harmonic2 + harmonic3 + harmonic4);
  }
}
