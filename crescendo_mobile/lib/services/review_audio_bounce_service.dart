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

/// Service for rendering MIDI notes to WAV and mixing with recorded audio.
/// Optimized for the new 48kHz hardware-synchronized standard.
class ReviewAudioBounceService {
  static const int defaultSampleRate = AudioConstants.audioSampleRate;
  static const double fadeInOutMs = 8.0; // 8ms fade in/out per note
  
  // Sine Lookup Table for performance optimization
  static const int _sineTableSize = 4096;
  static final Float32List _sineTable = _generateSineTable();
  
  static Float32List _generateSineTable() {
    final table = Float32List(_sineTableSize);
    for (var i = 0; i < _sineTableSize; i++) {
      table[i] = math.sin(2 * math.pi * i / _sineTableSize).toDouble();
    }
    return table;
  }
  
  /// Optimized sine function using lookup table
  @pragma('vm:prefer-inline')
  double _fastSin(double phase) {
    // phase is [0, 1]
    final index = (phase * _sineTableSize).toInt() & (_sineTableSize - 1);
    return _sineTable[index];
  }
  
  /// Generate a cache key for the bounced audio
  static String generateCacheKey({
    required String takeFileName,
    required String exerciseId,
    required int transposeSemitones,
    required int sampleRate,
    double renderStartSec = 0.0,
  }) {
    final keyString = '$takeFileName|$exerciseId|$transposeSemitones|$sampleRate|${renderStartSec.toStringAsFixed(3)}';
    final bytes = utf8.encode(keyString);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }
  
  static Future<Directory> getCacheDirectory() async {
    final cacheDir = await getApplicationCacheDirectory();
    final bounceDir = Directory(p.join(cacheDir.path, 'review_bounces'));
    if (!await bounceDir.exists()) {
      await bounceDir.create(recursive: true);
    }
    return bounceDir;
  }
  
  static Future<File?> getCachedMixedWav(String cacheKey) async {
    final cacheDir = await getCacheDirectory();
    final cachedFile = File(p.join(cacheDir.path, '${cacheKey}_mixed.wav'));
    if (await cachedFile.exists()) {
      return cachedFile;
    }
    return null;
  }
  
  /// Render reference notes to WAV file.
  /// Standardized at 48kHz for perfect hardware sync.
  Future<File> renderReferenceWav({
    required List<ReferenceNote> notes,
    required double durationSec,
    required int sampleRate,
    String? savePath,
  }) async {
    final startTime = DateTime.now();
    
    // 1. Generate float samples (synthesis)
    final samples = _generateSamples(
      notes: notes,
      sampleRate: sampleRate,
      durationSec: durationSec,
    );
    
    // 2. Convert to 16-bit PCM in-place
    final pcmSamples = Int16List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      // Inline clamping and scaling
      if (s >= 1.0) {
        pcmSamples[i] = 32767;
      } else if (s <= -1.0) {
        pcmSamples[i] = -32768;
      } else {
        pcmSamples[i] = (s * 32767.0).toInt();
      }
    }
    
    // 3. Write WAV file
    final String finalPath;
    if (savePath != null) {
      finalPath = savePath;
    } else {
      final cacheDir = await getCacheDirectory();
      finalPath = p.join(cacheDir.path, 'reference_${DateTime.now().millisecondsSinceEpoch}.wav');
    }

    await WavWriter.writePcm16Mono(
      samples: pcmSamples,
      sampleRate: sampleRate,
      path: finalPath,
    );
    
    final elapsed = DateTime.now().difference(startTime);
    debugPrint('[ReviewBounce] Reference WAV rendered in ${elapsed.inMilliseconds}ms at ${sampleRate}Hz');
    
    return File(finalPath);
  }
  
  /// Optimized samples generation
  Float32List _generateSamples({
    required List<ReferenceNote> notes,
    required int sampleRate,
    required double durationSec,
  }) {
    final totalFrames = (durationSec * sampleRate).ceil();
    final samples = Float32List(totalFrames);
    final fadeFrames = ((fadeInOutMs / 1000.0) * sampleRate).toInt();
    final invSampleRate = 1.0 / sampleRate;

    for (final note in notes) {
      final startFrame = (note.startSec * sampleRate).toInt();
      final endFrame = math.min((note.endSec * sampleRate).toInt(), totalFrames);
      final noteFrames = endFrame - startFrame;
      
      if (noteFrames <= 0 || startFrame >= totalFrames) continue;
      
      final hz = 440.0 * math.pow(2.0, (note.midi - 69.0) / 12.0);
      
      // Pre-calculate phase increments (normalized to [0, 1])
      final p1Cr = hz * invSampleRate;
      final p2Cr = p1Cr * 2.0;
      final p3Cr = p1Cr * 3.0;
      final p4Cr = p1Cr * 4.0;
      
      double p1 = 0.0, p2 = 0.0, p3 = 0.0, p4 = 0.0;
      
      for (var f = 0; f < noteFrames; f++) {
        final frameIndex = startFrame + f;
        if (frameIndex >= totalFrames) break;
        
        final noteTime = f * invSampleRate;
        
        // Sum harmonics using fast lookup
        final fundamental = _fastSin(p1);
        final harmonic2 = 0.6 * _fastSin(p2);
        final harmonic3 = 0.3 * _fastSin(p3);
        final harmonic4 = 0.15 * _fastSin(p4);
        
        // Advance phases
        p1 = (p1 + p1Cr); p1 -= p1.floor();
        p2 = (p2 + p2Cr); p2 -= p2.floor();
        p3 = (p3 + p3Cr); p3 -= p3.floor();
        p4 = (p4 + p4Cr); p4 -= p4.floor();
        
        // Envelope: 20ms attack, exponential decay
        final attack = (noteTime * 50.0); // 1.0 / 0.02
        final env = (attack < 1.0 ? attack : 1.0) * math.exp(-3.0 * noteTime);
        final val = 0.45 * env * (fundamental + harmonic2 + harmonic3 + harmonic4);
        
        // Apply fade in/out
        double fade = 1.0;
        if (f < fadeFrames) {
          fade = f / fadeFrames;
        } else if (f >= noteFrames - fadeFrames) {
          fade = (noteFrames - f) / fadeFrames;
        }
        
        samples[frameIndex] += (val * fade);
      }
    }
    
    return samples;
  }

  /// Mix two WAV files sample-by-sample (Optimized)
  Future<File> mixWavs({
    required File micWav,
    required File referenceWav,
    required double micGain,
    required double refGain,
    double micOffsetSec = 0.0,
    double refOffsetSec = 0.0,
    bool duckMicWhileRef = false,
  }) async {
    final startTime = DateTime.now();
    
    // Read both WAV files
    final micBytes = await micWav.readAsBytes();
    final refBytes = await referenceWav.readAsBytes();
    
    final micWavInfo = _parseWavHeader(micBytes);
    final refWavInfo = _parseWavHeader(refBytes);
    
    if (micWavInfo == null || refWavInfo == null) {
      throw Exception('Failed to parse WAV headers');
    }
    
    final sampleRate = micWavInfo.sampleRate;
    final micSamples = _readWavSamples(micBytes, micWavInfo);
    var refSamples = _readWavSamples(refBytes, refWavInfo);
    
    if (refWavInfo.sampleRate != sampleRate) {
      refSamples = _resample(refSamples, refWavInfo.sampleRate, sampleRate);
    }
    
    final micOffsetSamples = (micOffsetSec * sampleRate).round();
    final refOffsetSamples = (refOffsetSec * sampleRate).round();
    
    final outputLength = math.max(micSamples.length + micOffsetSamples, refSamples.length + refOffsetSamples);
    final pcmSamples = Int16List(outputLength);
    
    // Mix and convert to Int16 in one pass
    for (var i = 0; i < outputLength; i++) {
      final micIdx = i - micOffsetSamples;
      final refIdx = i - refOffsetSamples;
      
      var micVal = (micIdx >= 0 && micIdx < micSamples.length) ? micSamples[micIdx] * micGain : 0.0;
      final refVal = (refIdx >= 0 && refIdx < refSamples.length) ? refSamples[refIdx] * refGain : 0.0;
      
      if (duckMicWhileRef && refVal.abs() > 0.001) {
        micVal *= 0.3;
      }
      
      final mixed = (micVal + refVal);
      // Inline clamping and scaling
      if (mixed >= 1.0) {
        pcmSamples[i] = 32767;
      } else if (mixed <= -1.0) {
        pcmSamples[i] = -32768;
      } else {
        pcmSamples[i] = (mixed * 32767.0).toInt();
      }
    }
    
    final cacheDir = await getCacheDirectory();
    final mixedFile = File(p.join(cacheDir.path, 'mixed_${DateTime.now().millisecondsSinceEpoch}.wav'));
    await WavWriter.writePcm16Mono(
      samples: pcmSamples,
      sampleRate: sampleRate,
      path: mixedFile.path,
    );
    
    debugPrint('[ReviewBounce] Mixed WAV created in ${DateTime.now().difference(startTime).inMilliseconds}ms');
    return mixedFile;
  }

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
  
  _WavInfo? _parseWavHeader(Uint8List bytes) {
    if (bytes.length < 44) return null;
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') return null;
    if (String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') return null;

    int offset = 12;
    int? dataOffset, dataSize, sampleRate, channels, bitsPerSample;

    while (offset < bytes.length - 8) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = _readUint32(bytes, offset + 4);

      if (chunkId == 'fmt ') {
        if (_readUint16(bytes, offset + 8) != 1) return null;
        channels = _readUint16(bytes, offset + 10);
        sampleRate = _readUint32(bytes, offset + 12);
        bitsPerSample = _readUint16(bytes, offset + 22);
      } else if (chunkId == 'data') {
        dataOffset = offset + 8;
        dataSize = chunkSize;
        break;
      }
      offset += 8 + chunkSize;
      if (chunkSize % 2 == 1) offset++;
    }

    if (dataOffset == null || dataSize == null || sampleRate == null || channels == null || bitsPerSample == null) return null;
    return _WavInfo(sampleRate: sampleRate, channels: channels, bitsPerSample: bitsPerSample, dataOffset: dataOffset, dataSize: dataSize);
  }
  
  static int _readUint16(Uint8List bytes, int offset) => bytes[offset] | (bytes[offset + 1] << 8);
  static int _readUint32(Uint8List bytes, int offset) => bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24);
  
  Float32List _readWavSamples(Uint8List bytes, _WavInfo info) {
    final dataBytes = bytes.sublist(info.dataOffset, math.min(info.dataOffset + info.dataSize, bytes.length));
    if (info.bitsPerSample == 16) {
      final int16Samples = Int16List.view(dataBytes.buffer, dataBytes.offsetInBytes, dataBytes.length ~/ 2);
      final list = Float32List(int16Samples.length);
      for (var i = 0; i < int16Samples.length; i++) {
        list[i] = int16Samples[i] / 32768.0;
      }
      return list;
    }
    throw Exception('Unsupported bits: ${info.bitsPerSample}');
  }
}

class _WavInfo {
  final int sampleRate, channels, bitsPerSample, dataOffset, dataSize;
  _WavInfo({required this.sampleRate, required this.channels, required this.bitsPerSample, required this.dataOffset, required this.dataSize});
}
