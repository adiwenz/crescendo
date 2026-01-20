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
  print('');

  // Ensure output directory exists
  final outputDir = Directory('assets/audio/previews');
  if (!await outputDir.exists()) {
    await outputDir.create(recursive: true);
    print('Created directory: ${outputDir.path}');
  }

  // Generate each preview file
  final manifest = <String, double>{};

  manifest['siren_preview.wav'] = await _generateSirenPreview(outputDir);
  manifest['five_tone_scale_preview.wav'] =
      await _generateFiveToneScalePreview(outputDir);
  manifest['arpeggio_preview.wav'] = await _generateArpeggioPreview(outputDir);
  manifest['slides_preview.wav'] = await _generateSlidesPreview(outputDir);
  manifest['warmup_preview.wav'] = await _generateWarmupPreview(outputDir);
  manifest['agility_preview.wav'] = await _generateAgilityPreview(outputDir);
  manifest['yawn_sigh_preview.wav'] = await _generateYawnSighPreview(outputDir);
  manifest['interval_preview.wav'] = await _generateIntervalPreview(outputDir);
  manifest['descending_octave_preview.wav'] =
      await _generateDescendingOctavePreview(outputDir);

  print('');
  print('✓ All preview assets generated successfully!');
  print('');
  print('Generated files:');
  for (final entry in manifest.entries) {
    print('  ${entry.key}: ${entry.value.toStringAsFixed(2)}s');
  }
  print('');
  print('Files are in: ${outputDir.path}');
  print('');
  print('Next steps:');
  print('1. Verify the files sound correct');
  print('2. Commit the WAV files to git');
  print('3. Ensure pubspec.yaml includes: assets/audio/previews/');
}

// Generate siren preview: bell curve glide (up then down)
Future<double> _generateSirenPreview(Directory outputDir) async {
  print('Generating siren_preview.wav...');

  const durationSeconds = 4.0; // 4 seconds total
  const startMidi = 60.0; // C4
  const endMidi = 76.0; // E5
  const fadeOutSec = 0.02; // 20ms fade-out at end (no extra tail)
  const fadeInSec = 0.01; // 10ms fade-in

  final totalFrames = (durationSeconds * sampleRate).round();
  final samples = Float32List(totalFrames);

  // IMPORTANT: When frequency changes over time, you must integrate phase.
  double phase = 0.0;

  for (var i = 0; i < totalFrames; i++) {
    final t = i / sampleRate;
    final tNorm = (t / durationSeconds).clamp(0.0, 1.0);

    // Bell curve: 0 -> 1 -> 0 across the whole duration (up then down)
    final bell = math.sin(math.pi * tNorm);
    final midi = startMidi + (endMidi - startMidi) * bell;

    // MIDI -> Hz
    final hz = 440.0 * math.pow(2.0, (midi - 69.0) / 12.0);

    // Phase integration for variable frequency oscillator
    phase += 2.0 * math.pi * hz / sampleRate;

    var sample = math.sin(phase) * amplitude;

    // Fade-in (avoid click)
    if (t < fadeInSec) {
      sample *= (t / fadeInSec).clamp(0.0, 1.0);
    }

    // Fade-out (avoid click / no extra tail)
    if (t > durationSeconds - fadeOutSec) {
      final fadeProgress = ((durationSeconds - t) / fadeOutSec).clamp(0.0, 1.0);
      sample *= fadeProgress;
    }

    samples[i] = sample.toDouble();
  }

  final wavBytes = _encodeWav16Mono(samples);
  final file = File(p.join(outputDir.path, 'siren_preview.wav'));
  await file.writeAsBytes(wavBytes);

  print(
      '  ✓ Generated ${wavBytes.length} bytes, ${durationSeconds.toStringAsFixed(2)}s');
  return durationSeconds;
}

/// Generate 5-tone scale preview: Do-Re-Mi-Fa-Sol (5 notes only, NOT full octave)
/// FIX: Stop after 5 notes, do not continue to Do' or full octave
Future<double> _generateFiveToneScalePreview(Directory outputDir) async {
  print('Generating five_tone_scale_preview.wav...');

  // C major 5-tone scale: C4, D4, E4, F4, G4 (Do-Re-Mi-Fa-Sol)
  final scaleMidis = [60, 62, 64, 65, 67]; // 5 notes only
  const noteDurationSeconds = 0.4;
  const silenceDurationSeconds = 0.1;

  final allSamples = <double>[];

  for (var midi in scaleMidis) {
    // Generate note
    final noteSamples = _generateTone(midi.toDouble(), noteDurationSeconds);
    allSamples.addAll(noteSamples);

    // Add silence between notes (except after last note)
    if (midi != scaleMidis.last) {
      final silenceFrames = (silenceDurationSeconds * sampleRate).round();
      allSamples.addAll(List.filled(silenceFrames, 0.0));
    }
  }

  final durationSeconds = allSamples.length / sampleRate;
  final samples = Float32List.fromList(allSamples);
  final wavBytes = _encodeWav16Mono(samples);
  final file = File(p.join(outputDir.path, 'five_tone_scale_preview.wav'));
  await file.writeAsBytes(wavBytes);
  print(
      '  ✓ Generated ${wavBytes.length} bytes, ${durationSeconds.toStringAsFixed(2)}s (5 notes)');
  return durationSeconds;
}

/// Generate arpeggio preview: arpeggiated chord pattern
Future<double> _generateArpeggioPreview(Directory outputDir) async {
  print('Generating arpeggio_preview.wav...');

  // C major arpeggio: C4, E4, G4, C5
  final arpeggioMidis = [60, 64, 67, 72];
  const noteDurationSeconds = 0.5;
  const silenceDurationSeconds = 0.1;

  final allSamples = <double>[];

  for (var midi in arpeggioMidis) {
    final noteSamples = _generateTone(midi.toDouble(), noteDurationSeconds);
    allSamples.addAll(noteSamples);

    if (midi != arpeggioMidis.last) {
      final silenceFrames = (silenceDurationSeconds * sampleRate).round();
      allSamples.addAll(List.filled(silenceFrames, 0.0));
    }
  }

  final durationSeconds = allSamples.length / sampleRate;
  final samples = Float32List.fromList(allSamples);
  final wavBytes = _encodeWav16Mono(samples);
  final file = File(p.join(outputDir.path, 'arpeggio_preview.wav'));
  await file.writeAsBytes(wavBytes);
  print(
      '  ✓ Generated ${wavBytes.length} bytes, ${durationSeconds.toStringAsFixed(2)}s');
  return durationSeconds;
}

/// Generate slides preview: upward glide (octave slide pattern)
Future<double> _generateSlidesPreview(Directory outputDir) async {
  print('Generating slides_preview.wav...');

  const startMidi = 60.0; // C4
  const endMidi = 72.0; // C5 (octave up)
  const durationSeconds = 1.5;
  const fadeSeconds = 0.05;

  final samples =
      _generateSweep(startMidi, endMidi, durationSeconds, fadeSeconds);
  final wavBytes = _encodeWav16Mono(samples);
  final file = File(p.join(outputDir.path, 'slides_preview.wav'));
  await file.writeAsBytes(wavBytes);
  print(
      '  ✓ Generated ${wavBytes.length} bytes, ${durationSeconds.toStringAsFixed(2)}s');
  return durationSeconds;
}

/// Generate warmup preview: sustained tone (for warmup exercises)
Future<double> _generateWarmupPreview(Directory outputDir) async {
  print('Generating warmup_preview.wav...');

  const midi = 60.0; // C4
  const durationSeconds = 3.0;
  const fadeSeconds = 0.1;

  final samples = _generateTone(midi, durationSeconds, fadeSeconds);
  final wavBytes = _encodeWav16Mono(samples);
  final file = File(p.join(outputDir.path, 'warmup_preview.wav'));
  await file.writeAsBytes(wavBytes);
  print(
      '  ✓ Generated ${wavBytes.length} bytes, ${durationSeconds.toStringAsFixed(2)}s');
  return durationSeconds;
}

/// Generate agility preview: fast three-note pattern
Future<double> _generateAgilityPreview(Directory outputDir) async {
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

  final durationSeconds = allSamples.length / sampleRate;
  final samples = Float32List.fromList(allSamples);
  final wavBytes = _encodeWav16Mono(samples);
  final file = File(p.join(outputDir.path, 'agility_preview.wav'));
  await file.writeAsBytes(wavBytes);
  print(
      '  ✓ Generated ${wavBytes.length} bytes, ${durationSeconds.toStringAsFixed(2)}s');
  return durationSeconds;
}

/// Generate YawnSigh preview: descending glide (smooth downward sweep)
/// FIX: Single continuous descending glide, not stepped notes, not octave run
Future<double> _generateYawnSighPreview(Directory outputDir) async {
  print('Generating yawn_sigh_preview.wav...');

  const startMidi = 72.0; // C5 (start high)
  const endMidi = 60.0; // C4 (descend to lower)
  const durationSeconds = 2.0; // 2 second smooth glide down
  const fadeSeconds = 0.05;

  final samples =
      _generateSweep(startMidi, endMidi, durationSeconds, fadeSeconds);
  final wavBytes = _encodeWav16Mono(samples);
  final file = File(p.join(outputDir.path, 'yawn_sigh_preview.wav'));
  await file.writeAsBytes(wavBytes);
  print(
      '  ✓ Generated ${wavBytes.length} bytes, ${durationSeconds.toStringAsFixed(2)}s (descending glide)');
  return durationSeconds;
}

/// Generate interval preview: Do->Sol interval (2 notes: C4 then G4)
/// FIX: Replace octave-scale preview with simple interval demo
Future<double> _generateIntervalPreview(Directory outputDir) async {
  print('Generating interval_preview.wav...');

  // Interval demo: Do (C4) then Sol (G4)
  final intervalMidis = [60, 67]; // C4, G4
  const noteDurationSeconds = 0.6;
  const silenceDurationSeconds = 0.15;

  final allSamples = <double>[];

  for (var midi in intervalMidis) {
    final noteSamples = _generateTone(midi.toDouble(), noteDurationSeconds);
    allSamples.addAll(noteSamples);

    if (midi != intervalMidis.last) {
      final silenceFrames = (silenceDurationSeconds * sampleRate).round();
      allSamples.addAll(List.filled(silenceFrames, 0.0));
    }
  }

  final durationSeconds = allSamples.length / sampleRate;
  final samples = Float32List.fromList(allSamples);
  final wavBytes = _encodeWav16Mono(samples);
  final file = File(p.join(outputDir.path, 'interval_preview.wav'));
  await file.writeAsBytes(wavBytes);
  print(
      '  ✓ Generated ${wavBytes.length} bytes, ${durationSeconds.toStringAsFixed(2)}s (Do->Sol interval)');
  return durationSeconds;
}

/// Generate descending octave preview: descending octave scale (C5 down to C4)
/// FIX: Explicitly descending octave scale
Future<double> _generateDescendingOctavePreview(Directory outputDir) async {
  print('Generating descending_octave_preview.wav...');

  // Descending octave scale: C5, B4, A4, G4, F4, E4, D4, C4
  final descendingMidis = [72, 71, 69, 67, 65, 64, 62, 60];
  const noteDurationSeconds = 0.4;
  const silenceDurationSeconds = 0.1;

  final allSamples = <double>[];

  for (var midi in descendingMidis) {
    final noteSamples = _generateTone(midi.toDouble(), noteDurationSeconds);
    allSamples.addAll(noteSamples);

    if (midi != descendingMidis.last) {
      final silenceFrames = (silenceDurationSeconds * sampleRate).round();
      allSamples.addAll(List.filled(silenceFrames, 0.0));
    }
  }

  final durationSeconds = allSamples.length / sampleRate;
  final samples = Float32List.fromList(allSamples);
  final wavBytes = _encodeWav16Mono(samples);
  final file = File(p.join(outputDir.path, 'descending_octave_preview.wav'));
  await file.writeAsBytes(wavBytes);
  print(
      '  ✓ Generated ${wavBytes.length} bytes, ${durationSeconds.toStringAsFixed(2)}s (descending octave scale)');
  return durationSeconds;
}

/// Generate a steady tone
Float32List _generateTone(double midi, double durationSeconds,
    [double fadeSeconds = 0.05]) {
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
Float32List _generateSweep(double startMidi, double endMidi,
    double durationSeconds, double fadeSeconds) {
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
  header.setUint32(offset, fileSize, Endian.little);
  offset += 4;
  header.setUint8(offset++, 0x57); // 'W'
  header.setUint8(offset++, 0x41); // 'A'
  header.setUint8(offset++, 0x56); // 'V'
  header.setUint8(offset++, 0x45); // 'E'

  // fmt chunk
  header.setUint8(offset++, 0x66); // 'f'
  header.setUint8(offset++, 0x6D); // 'm'
  header.setUint8(offset++, 0x74); // 't'
  header.setUint8(offset++, 0x20); // ' '
  header.setUint32(offset, 16, Endian.little);
  offset += 4; // fmt chunk size
  header.setUint16(offset, 1, Endian.little);
  offset += 2; // PCM format
  header.setUint16(offset, 1, Endian.little);
  offset += 2; // mono
  header.setUint32(offset, sampleRate, Endian.little);
  offset += 4;
  header.setUint32(offset, sampleRate * 2, Endian.little);
  offset += 4; // byte rate
  header.setUint16(offset, 2, Endian.little);
  offset += 2; // block align
  header.setUint16(offset, 16, Endian.little);
  offset += 2; // bits per sample

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
