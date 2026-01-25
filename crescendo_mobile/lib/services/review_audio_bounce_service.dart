import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/reference_note.dart';
import '../audio/wav_writer.dart';
import '../utils/audio_constants.dart';

/// Service for rendering MIDI notes to WAV and mixing with recorded audio
/// This eliminates timer-based real-time MIDI scheduling during review playback
class ReviewAudioBounceService {
  static const int defaultSampleRate = AudioConstants.audioSampleRate;
  static const double fadeInOutMs = 8.0; // 8ms fade in/out per note
  
  // Sine Lookup Table for performance optimization
  static const int _sineTableSize = 4096;
  static final Float32List _sineTable = _generateSineTable();
  
  static Float32List _generateSineTable() {
    final table = Float32List(_sineTableSize);
    for (var i = 0; i < _sineTableSize; i++) {
      table[i] = math.sin(2 * math.pi * i / _sineTableSize);
    }
    return table;
  }
  
  /// Optimized sine function using lookup table
  double _fastSin(double phase) {
    // Normalize phase to [0, 1]
    final normalized = phase - phase.floor();
    final index = (normalized * _sineTableSize).floor() % _sineTableSize;
    return _sineTable[index];
  }
  
  /// Generate a cache key for the bounced audio
  static String generateCacheKey({
    required String takeFileName,
    required String exerciseId,
    required int transposeSemitones,
    required String soundFontName,
    required int program,
    required int sampleRate,
    double renderStartSec = 0.0,
  }) {
    final keyString = '$takeFileName|$exerciseId|$transposeSemitones|$soundFontName|$program|$sampleRate|${renderStartSec.toStringAsFixed(3)}';
    final bytes = utf8.encode(keyString);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16); // Use first 16 chars of hash
  }
  
  /// Get the cache directory for bounced audio
  static Future<Directory> getCacheDirectory() async {
    final cacheDir = await getApplicationCacheDirectory();
    final bounceDir = Directory(p.join(cacheDir.path, 'review_bounces'));
    if (!await bounceDir.exists()) {
      await bounceDir.create(recursive: true);
    }
    return bounceDir;
  }
  
  /// Get cached mixed WAV file path if it exists
  static Future<File?> getCachedMixedWav(String cacheKey) async {
    final cacheDir = await getCacheDirectory();
    final cachedFile = File(p.join(cacheDir.path, '${cacheKey}_mixed.wav'));
    if (await cachedFile.exists()) {
      if (kDebugMode) {
        debugPrint('[ReviewBounce] Found cached mixed WAV: ${cachedFile.path}');
      }
      return cachedFile;
    }
    return null;
  }
  
  /// Render reference notes to WAV file
  /// Uses simple piano synth (same as AudioSynthService) for consistency
  Future<File> renderReferenceWav({
    required List<ReferenceNote> notes,
    required double durationSec,
    required int sampleRate,
    required String soundFontAssetPath,
    required int program,
    String? savePath,
  }) async {
    final startTime = DateTime.now();
    
    if (kDebugMode) {
      debugPrint('[ReviewBounce] Rendering reference WAV: ${notes.length} notes, duration=${durationSec.toStringAsFixed(2)}s, sampleRate=$sampleRate');
    }
    
    // Generate samples using optimized synthesis
    final samples = _generateSamples(
      notes: notes,
      sampleRate: sampleRate,
      durationSec: durationSec,
    );
    
    // Convert to 16-bit PCM using efficient loop
    final pcmSamples = Int16List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      final clamped = s < -1.0 ? -1.0 : (s > 1.0 ? 1.0 : s);
      pcmSamples[i] = (clamped * 32767.0).round();
    }
    
    // Write WAV file
    String finalPath;
    if (savePath != null) {
      finalPath = savePath;
    } else {
      final cacheDir = await getCacheDirectory();
      finalPath = p.join(cacheDir.path, 'reference_${DateTime.now().millisecondsSinceEpoch}.wav');
    }

    await WavWriter.writePcm16Mono(
      samples: pcmSamples.toList(), // Convert back to list for existing WavWriter
      sampleRate: sampleRate,
      path: finalPath,
    );
    
    final elapsed = DateTime.now().difference(startTime);
    if (kDebugMode) {
      final firstNonZero = _findFirstNonZeroSample(pcmSamples);
      final lastNonZero = _findLastNonZeroSample(pcmSamples);
      debugPrint('[ReviewBounce] Reference WAV rendered in ${elapsed.inMilliseconds}ms: $finalPath');
      debugPrint('[ReviewBounce] First non-zero sample: $firstNonZero, last non-zero: $lastNonZero');
    }
    
    return File(finalPath);
  }
  
  /// Mix two WAV files sample-by-sample
  Future<File> mixWavs({
    required File micWav,
    required File referenceWav,
    required double micGain,
    required double refGain,
    double micOffsetSec = 0.0,
    bool duckMicWhileRef = false,
  }) async {
    final startTime = DateTime.now();
    
    if (kDebugMode) {
      debugPrint('[ReviewBounce] Mixing WAVs: mic=${micWav.path}, ref=${referenceWav.path}, offset=${micOffsetSec.toStringAsFixed(3)}s');
      debugPrint('[ReviewBounce] Gains: mic=$micGain, ref=$refGain, duckMic=$duckMicWhileRef');
    }
    
    // Read both WAV files
    final micBytes = await micWav.readAsBytes();
    final refBytes = await referenceWav.readAsBytes();
    
    // Parse WAV headers manually
    final micWavInfo = _parseWavHeader(micBytes);
    final refWavInfo = _parseWavHeader(refBytes);
    
    if (micWavInfo == null || refWavInfo == null) {
      throw Exception('Failed to parse WAV headers');
    }
    
    if (micWavInfo.sampleRate != refWavInfo.sampleRate) {
      if (kDebugMode) {
        debugPrint('[ReviewBounce] Resampling reference from ${refWavInfo.sampleRate} to ${micWavInfo.sampleRate}');
      }
    }
    
    final sampleRate = micWavInfo.sampleRate;
    final micSamples = _readWavSamples(micBytes, micWavInfo);
    var refSamples = _readWavSamples(refBytes, refWavInfo);
    
    // Resample reference if needed
    if (refWavInfo.sampleRate != sampleRate) {
      refSamples = _resample(refSamples, refWavInfo.sampleRate, sampleRate);
    }
    
    if (kDebugMode) {
      final micMax = micSamples.isEmpty ? 0.0 : micSamples.map((s) => s.abs()).reduce(math.max);
      final refMax = refSamples.isEmpty ? 0.0 : refSamples.map((s) => s.abs()).reduce(math.max);
      debugPrint('[ReviewBounce] Signal Check: micMax=${micMax.toStringAsFixed(3)}, refMax=${refMax.toStringAsFixed(3)}');
    }
    
    final micOffsetSamples = (micOffsetSec * sampleRate).round();
    
    // Determine output length (use the longer of the two, accounting for offset)
    final outputLength = math.max(micSamples.length + micOffsetSamples, refSamples.length);
    final mixedSamples = Float32List(outputLength);
    
    // Mix sample-by-sample
    for (var i = 0; i < outputLength; i++) {
      final micSampleIdx = i - micOffsetSamples;
      var micSample = (micSampleIdx >= 0 && micSampleIdx < micSamples.length) ? micSamples[micSampleIdx] * micGain : 0.0;
      var refSample = i < refSamples.length ? refSamples[i] * refGain : 0.0;
      
      // Duck mic while reference is playing (if enabled)
      if (duckMicWhileRef && refSample.abs() > 0.001) {
        micSample *= 0.3; // Reduce mic by 70% when reference is playing
      }
      
      // Mix and clamp
      final mixed = (micSample + refSample).clamp(-1.0, 1.0);
      mixedSamples[i] = mixed;
    }
    
    // Convert to 16-bit PCM
    final pcmSamples = mixedSamples.map((s) {
      return (s * 32767.0).round().clamp(-32768, 32767);
    }).toList();
    
    // Write mixed WAV
    final cacheDir = await getCacheDirectory();
    final mixedFile = File(p.join(cacheDir.path, 'mixed_${DateTime.now().millisecondsSinceEpoch}.wav'));
    await WavWriter.writePcm16Mono(
      samples: pcmSamples,
      sampleRate: sampleRate,
      path: mixedFile.path,
    );
    
    final elapsed = DateTime.now().difference(startTime);
    if (kDebugMode) {
      final firstNonZero = _findFirstNonZeroSample(pcmSamples);
      final lastNonZero = _findLastNonZeroSample(pcmSamples);
      debugPrint('[ReviewBounce] Mixed WAV created in ${elapsed.inMilliseconds}ms: ${mixedFile.path}');
      debugPrint('[ReviewBounce] Mixed WAV: first non-zero=$firstNonZero, last non-zero=$lastNonZero, length=${pcmSamples.length} samples');
    }
    
    return mixedFile;
  }
  
  /// Generate audio samples from reference notes
  /// Optimized using typed data and sine lookup
  Float32List _generateSamples({
    required List<ReferenceNote> notes,
    required int sampleRate,
    required double durationSec,
  }) {
    final totalFrames = (durationSec * sampleRate).ceil();
    final samples = Float32List(totalFrames);
    final fadeFrames = ((fadeInOutMs / 1000.0) * sampleRate).round();
    
    for (final note in notes) {
      final startFrame = (note.startSec * sampleRate).round();
      final endFrame = math.min((note.endSec * sampleRate).round(), totalFrames);
      final noteFrames = endFrame - startFrame;
      
      if (noteFrames <= 0 || startFrame < 0 || startFrame >= totalFrames) continue;
      
      final hz = 440.0 * math.pow(2.0, (note.midi - 69.0) / 12.0);
      final phaseStep = hz / sampleRate;
      
      for (var f = 0; f < noteFrames; f++) {
        final frameIndex = startFrame + f;
        if (frameIndex >= totalFrames) break;
        
        final noteTime = f / sampleRate;
        final phase = noteTime * hz;
        
        // Sum harmonics using fast lookup
        final fundamental = _fastSin(phase);
        final harmonic2 = 0.6 * _fastSin(phase * 2);
        final harmonic3 = 0.3 * _fastSin(phase * 3);
        final harmonic4 = 0.15 * _fastSin(phase * 4);
        
        final attack = (noteTime / 0.02);
        final env = (attack < 1.0 ? attack : 1.0) * math.exp(-3.0 * noteTime);
        final sample = 0.45 * env * (fundamental + harmonic2 + harmonic3 + harmonic4);
        
        // Apply fade in/out
        double fade = 1.0;
        if (f < fadeFrames) {
          fade = f / fadeFrames;
        } else if (f >= noteFrames - fadeFrames) {
          fade = (noteFrames - f) / fadeFrames;
        }
        
        samples[frameIndex] += (sample * fade);
      }
    }
    
    return samples;
  }

  /// Linear interpolation resampler
  Float32List _resample(Float32List input, int fromRate, int toRate) {
    if (fromRate == toRate) return input;
    
    final ratio = toRate / fromRate;
    final outputLength = (input.length * ratio).round();
    final output = Float32List(outputLength);
    
    for (var i = 0; i < outputLength; i++) {
      final inputPos = i / ratio;
      final idx = inputPos.floor();
      final frac = inputPos - idx;
      
      if (idx >= input.length - 1) {
        output[i] = idx < input.length ? input[idx] : 0.0;
      } else {
        final s1 = input[idx];
        final s2 = input[idx + 1];
        output[i] = s1 + (s2 - s1) * frac;
      }
    }
    
    return output;
  }
  
  /// Piano sample generator (same as AudioSynthService)
  double _pianoSample(double hz, double noteTime) {
    final attack = (noteTime / 0.02).clamp(0.0, 1.0);
    final decay = math.exp(-3.0 * noteTime);
    final env = attack * decay;
    final fundamental = math.sin(2 * math.pi * hz * noteTime);
    final harmonic2 = 0.6 * math.sin(2 * math.pi * hz * 2 * noteTime);
    final harmonic3 = 0.3 * math.sin(2 * math.pi * hz * 3 * noteTime);
    final harmonic4 = 0.15 * math.sin(2 * math.pi * hz * 4 * noteTime);
    return 0.45 * env * (fundamental + harmonic2 + harmonic3 + harmonic4);
  }
  
  /// Parse WAV file header
  _WavInfo? _parseWavHeader(Uint8List bytes) {
    if (bytes.length < 44) return null;

    // Check RIFF header
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    if (riff != 'RIFF') return null;

    // Check WAVE format
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (wave != 'WAVE') return null;

    // Find fmt chunk
    int offset = 12;
    int? dataOffset;
    int? dataSize;
    int? sampleRate;
    int? channels;
    int? bitsPerSample;

    while (offset < bytes.length - 8) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = _readUint32(bytes, offset + 4);

      if (chunkId == 'fmt ') {
        // Parse fmt chunk
        final audioFormat = _readUint16(bytes, offset + 8);
        if (audioFormat != 1) {
          if (kDebugMode) {
            debugPrint('[ReviewBounce] Unsupported audio format: $audioFormat (expected 1 = PCM)');
          }
          return null;
        }
        channels = _readUint16(bytes, offset + 10);
        sampleRate = _readUint32(bytes, offset + 12);
        _readUint32(bytes, offset + 16); // byteRate (unused)
        _readUint16(bytes, offset + 20); // blockAlign (unused)
        bitsPerSample = _readUint16(bytes, offset + 22);
      } else if (chunkId == 'data') {
        dataOffset = offset + 8;
        dataSize = chunkSize;
        break;
      }

      offset += 8 + chunkSize;
      // Align to even boundary
      if (chunkSize % 2 == 1) offset++;
    }

    if (dataOffset == null || dataSize == null || sampleRate == null || 
        channels == null || bitsPerSample == null) {
      return null;
    }

    return _WavInfo(
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
      dataOffset: dataOffset,
      dataSize: dataSize,
    );
  }
  
  static int _readUint16(Uint8List bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  static int _readUint32(Uint8List bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }
  
  /// Read WAV samples as Float32List
  Float32List _readWavSamples(Uint8List bytes, _WavInfo info) {
    final dataStart = info.dataOffset;
    final dataEnd = dataStart + info.dataSize;
    final dataBytes = bytes.sublist(dataStart, math.min(dataEnd, bytes.length));
    
    if (info.bitsPerSample == 16) {
      final int16Samples = Int16List.view(dataBytes.buffer, dataBytes.offsetInBytes, dataBytes.length ~/ 2);
      return Float32List(int16Samples.length).also((list) {
        for (var i = 0; i < int16Samples.length; i++) {
          list[i] = int16Samples[i] / 32768.0;
        }
      });
    } else {
      throw Exception('Unsupported bits per sample: ${info.bitsPerSample}');
    }
  }
  
  /// Find first non-zero sample index
  int _findFirstNonZeroSample(List<int> samples) {
    for (var i = 0; i < samples.length; i++) {
      if (samples[i].abs() > 10) return i; // Threshold to ignore noise
    }
    return -1;
  }
  
  /// Find last non-zero sample index
  int _findLastNonZeroSample(List<int> samples) {
    for (var i = samples.length - 1; i >= 0; i--) {
      if (samples[i].abs() > 10) return i; // Threshold to ignore noise
    }
    return -1;
  }
}

/// WAV file info structure
class _WavInfo {
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int dataOffset;
  final int dataSize;
  
  _WavInfo({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataSize,
  });
}

/// Extension to add `also` method for chaining
extension Also<T> on T {
  T also(void Function(T) block) {
    block(this);
    return this;
  }
}
