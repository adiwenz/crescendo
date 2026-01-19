#!/usr/bin/env dart
/// Dev-only utility to generate preview WAV files for exercise previews.
/// 
/// Usage:
///   dart tool/generate_preview_assets.dart
/// 
/// This script generates WAV files in assets/audio/previews/ that are bundled
/// with the app. These files are used for instant preview playback without
/// runtime generation.
/// 
/// DO NOT run this in production builds or ship this script.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:path/path.dart' as p;

const int sampleRate = 44100;
const double amplitude = 0.2; // Safe volume level (no clipping)

void main() async {
  print('Generating preview audio assets...');
  
  // Ensure output directory exists
  final outputDir = Directory('assets/audio/previews');
  if (!await outputDir.exists()) {
    await outputDir.create(recursive: true);
    print('Created directory: ${outputDir.path}');
  }
  
  // Generate each preview file
  await _generateSirenPreview(outputDir);
  await _generateScalesPreview(outputDir);
  await _generateArpeggioPreview(outputDir);
  await _generateSlidesPreview(outputDir);
  await _generateWarmupPreview(outputDir);
  await _generateAgilityPreview(outputDir);
  
  print('\n✓ All preview assets generated successfully!');
  print('Files are in: ${outputDir.path}');
  print('\nNext steps:');
  print('1. Verify the files sound correct');
  print('2. Commit the WAV files to git');
  print('3. Ensure pubspec.yaml includes: assets/audio/previews/');
}

/// Generate siren preview: continuous glide up then down (bell curve shape)
Future<void> _generateSirenPreview(Directory outputDir) async {
  print('Generating siren_preview.wav...');
  
  const durationSeconds = 4.0; // 4 seconds total
  const startMidi = 60.0; // C4
  const endMidi = 76.0; // E5
  const fadeSeconds = 0.05;
  
  // Generate bell curve: up then down
  final samples = Float32List((durationSeconds * sampleRate).round());
  final halfDuration = durationSeconds / 2.0;
  
  for (var i = 0; i < samples.length; i++) {
    final t = i / sampleRate;
    final tNorm = t / durationSeconds; // Normalized [0..1]
    
    // Bell curve: sin(π * tNorm) gives 0 -> 1 -> 0
    final bellCurve = math.sin(math.pi * tNorm);
    final midi = startMidi + (endMidi - startMidi) * bellCurve;
    final hz = 440.0 * math.pow(2.0, (midi - 69.0) / 12.0);
    
    // Generate sine wave sample
    final phase = 2.0 * math.pi * hz * t;
    var sample = math.sin(phase) * amplitude;
    
    // Apply fade in/out
    if (t < fadeSeconds) {
      sample *= t / fadeSeconds;
    } else if (t > durationSeconds - fadeSeconds) {
      sample *= (durationSeconds - t) / fadeSeconds;
    }
    
    samples[i] = sample;
  }
  
  final wavBytes = _encodeWav16Mono(samples);
  final file = File(p.join(outputDir.path, 'siren_preview.wav'));
  await file.writeAsBytes(wavBytes);
  print('  ✓ Generated ${wavBytes.length} bytes');
}

/// Generate scales preview: ascending scale pattern
Future<void> _generateScalesPreview(Directory outputDir) async {
  print('Generating scales_preview.wav...');
  
  // C major scale: C4, D4, E4, F4, G4, A4, B4, C5
  final scaleMidis = [60, 62, 64, 65, 67, 69, 71, 72];
  const noteDurationSeconds = 0.4;
  const silenceDurationSeconds = 0.1;
  
  final allSamples = <double>[];
  
  for (var midi in scaleMidis) {
    // Generate note
    final noteSamples = _generateTone(midi.toDouble(), noteDurationSeconds);
    allSamples.addAll(noteSamples);
    
    // Add silence between notes
    final silenceFrames = (silenceDurationSeconds * sampleRate).round();
    allSamples.addAll(List.filled(silenceFrames, 0.0));
  }
  
  final samples = Float32List.fromList(allSamples);
  final wavBytes = _encodeWav16Mono(samples);
  final file = File(p.join(outputDir.path, 'scales_preview.wav'));
  await file.writeAsBytes(wavBytes);
  print('  ✓ Generated ${wavBytes.length} bytes');
}

/// Generate arpeggio preview: arpeggiated chord pattern
Future<void> _generateArpeggioPreview(Directory outputDir) async {
  print('Generating arpeggio_preview.wav...');
  
  // C major arpeggio: C4, E4, G4, C5
  final arpeggioMidis = [60, 64, 67, 72];
  const noteDurationSeconds = 0.5;
  const silenceDurationSeconds = 0.1;
  
  final allSamples = <double>[];
  
  for (var midi in arpeggioMidis) {
    final noteSamples = _generateTone(midi.toDouble(), noteDurationSeconds);
    allSamples.addAll(noteSamples);
    
    final silenceFrames = (silenceDurationSeconds * sampleRate).round();
    allSamples.addAll(List.filled(silenceFrames, 0.0));
  }
  
  final samples = Float32List.fromList(allSamples);
  final wavBytes = _encodeWav16Mono(samples);
  final file = File(p.join(outputDir.path, 'arpeggio_preview.wav'));
  await file.writeAsBytes(wavBytes);
  print('  ✓ Generated ${wavBytes.length} bytes');
}

/// Generate slides preview: upward glide (octave slide pattern)
Future<void> _generateSlidesPreview(Directory outputDir) async {
  print('Generating slides_preview.wav...');
  
  const startMidi = 60.0; // C4
  const endMidi = 72.0; // C5 (octave up)
  const durationSeconds = 1.5;
  const fadeSeconds = 0.05;
  
  final samples = _generateSweep(startMidi, endMidi, durationSeconds, fadeSeconds);
  final wavBytes = _encodeWav16Mono(samples);
  final file = File(p.join(outputDir.path, 'slides_preview.wav'));
  await file.writeAsBytes(wavBytes);
  print('  ✓ Generated ${wavBytes.length} bytes');
}

/// Generate warmup preview: sustained tone (for warmup exercises)
Future<void> _generateWarmupPreview(Directory outputDir) async {
  print('Generating warmup_preview.wav...');
  
  const midi = 60.0; // C4
  const durationSeconds = 3.0;
  const fadeSeconds = 0.1;
  
  final samples = _generateTone(midi, durationSeconds, fadeSeconds);
  final wavBytes = _encodeWav16Mono(samples);
  final file = File(p.join(outputDir.path, 'warmup_preview.wav'));
  await file.writeAsBytes(wavBytes);
  print('  ✓ Generated ${wavBytes.length} bytes');
}

/// Generate agility preview: fast three-note pattern
Future<void> _generateAgilityPreview(Directory outputDir) async {
  print('Generating agility_preview.wav...');
  
  // Fast three-note pattern: C4, E4, G4 repeated
  final patternMidis = [60, 64, 67];
  const noteDurationSeconds = 0.2;
  const silenceDurationSeconds = 0.05;
  
  final allSamples = <double>[];
  
  // Repeat pattern twice
  for (var repeat = 0; repeat < 2; repeat++) {
    for (var midi in patternMidis) {
      final noteSamples = _generateTone(midi.toDouble(), noteDurationSeconds);
      allSamples.addAll(noteSamples);
      
      final silenceFrames = (silenceDurationSeconds * sampleRate).round();
      allSamples.addAll(List.filled(silenceFrames, 0.0));
    }
  }
  
  final samples = Float32List.fromList(allSamples);
  final wavBytes = _encodeWav16Mono(samples);
  final file = File(p.join(outputDir.path, 'agility_preview.wav'));
  await file.writeAsBytes(wavBytes);
  print('  ✓ Generated ${wavBytes.length} bytes');
}

/// Generate a steady tone
Float32List _generateTone(double midi, double durationSeconds, [double fadeSeconds = 0.05]) {
  final hz = 440.0 * math.pow(2.0, (midi - 69.0) / 12.0);
  final frames = (durationSeconds * sampleRate).round();
  final samples = Float32List(frames);
  
  for (var i = 0; i < frames; i++) {
    final t = i / sampleRate;
    final phase = 2.0 * math.pi * hz * t;
    var sample = math.sin(phase) * amplitude;
    
    // Apply fade in/out
    if (t < fadeSeconds) {
      sample *= t / fadeSeconds;
    } else if (t > durationSeconds - fadeSeconds) {
      sample *= (durationSeconds - t) / fadeSeconds;
    }
    
    samples[i] = sample;
  }
  
  return samples;
}

/// Generate a frequency sweep (glide)
Float32List _generateSweep(double startMidi, double endMidi, double durationSeconds, double fadeSeconds) {
  final frames = (durationSeconds * sampleRate).round();
  final samples = Float32List(frames);
  
  for (var i = 0; i < frames; i++) {
    final t = i / sampleRate;
    final tNorm = t / durationSeconds; // Normalized [0..1]
    
    // Linear interpolation of MIDI
    final midi = startMidi + (endMidi - startMidi) * tNorm;
    final hz = 440.0 * math.pow(2.0, (midi - 69.0) / 12.0);
    
    // Generate sine wave sample
    final phase = 2.0 * math.pi * hz * t;
    var sample = math.sin(phase) * amplitude;
    
    // Apply fade in/out
    if (t < fadeSeconds) {
      sample *= t / fadeSeconds;
    } else if (t > durationSeconds - fadeSeconds) {
      sample *= (durationSeconds - t) / fadeSeconds;
    }
    
    samples[i] = sample;
  }
  
  return samples;
}

/// Encode Float32 samples to 16-bit PCM WAV format
Uint8List _encodeWav16Mono(Float32List samples) {
  // Convert float32 to int16
  final int16Samples = Int16List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    int16Samples[i] = (samples[i] * 32767).round().clamp(-32768, 32767);
  }
  
  // WAV header
  final dataSize = int16Samples.length * 2; // 2 bytes per sample
  final fileSize = 36 + dataSize; // Header size + data size
  
  final header = ByteData(44);
  var offset = 0;
  
  // RIFF header
  header.setUint8(offset++, 0x52); // 'R'
  header.setUint8(offset++, 0x49); // 'I'
  header.setUint8(offset++, 0x46); // 'F'
  header.setUint8(offset++, 0x46); // 'F'
  header.setUint32(offset, fileSize, Endian.little); offset += 4;
  header.setUint8(offset++, 0x57); // 'W'
  header.setUint8(offset++, 0x41); // 'A'
  header.setUint8(offset++, 0x56); // 'V'
  header.setUint8(offset++, 0x45); // 'E'
  
  // fmt chunk
  header.setUint8(offset++, 0x66); // 'f'
  header.setUint8(offset++, 0x6D); // 'm'
  header.setUint8(offset++, 0x74); // 't'
  header.setUint8(offset++, 0x20); // ' '
  header.setUint32(offset, 16, Endian.little); offset += 4; // fmt chunk size
  header.setUint16(offset, 1, Endian.little); offset += 2; // PCM format
  header.setUint16(offset, 1, Endian.little); offset += 2; // mono
  header.setUint32(offset, sampleRate, Endian.little); offset += 4;
  header.setUint32(offset, sampleRate * 2, Endian.little); offset += 4; // byte rate
  header.setUint16(offset, 2, Endian.little); offset += 2; // block align
  header.setUint16(offset, 16, Endian.little); offset += 2; // bits per sample
  
  // data chunk
  header.setUint8(offset++, 0x64); // 'd'
  header.setUint8(offset++, 0x61); // 'a'
  header.setUint8(offset++, 0x74); // 't'
  header.setUint8(offset++, 0x61); // 'a'
  header.setUint32(offset, dataSize, Endian.little);
  
  // Combine header + samples
  final bytes = Uint8List(44 + dataSize);
  bytes.setRange(0, 44, header.buffer.asUint8List());
  bytes.setRange(44, 44 + dataSize, int16Samples.buffer.asUint8List());
  
  return bytes;
}
