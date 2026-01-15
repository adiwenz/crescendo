import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Service for generating smooth sine wave sweeps (glides) between MIDI notes.
/// Uses continuous phase accumulation to prevent clicks and pops.
class SineSweepService {
  final int sampleRate;

  SineSweepService({this.sampleRate = 44100});

  /// Convert MIDI note number to frequency in Hz
  double _midiToHz(double midi) => 440.0 * pow(2.0, (midi - 69.0) / 12.0);

  /// Generate a smooth sine sweep from startMidi to endMidi over durationSeconds.
  /// Uses linear interpolation in semitone space with continuous phase accumulation.
  Float32List generateSineSweep({
    required double midiStart,
    required double midiEnd,
    required double durationSeconds,
    double amplitude = 0.2,
    double fadeSeconds = 0.01,
  }) {
    final int n = max(2, (durationSeconds * sampleRate).round());
    final out = Float32List(n);

    final int fadeN = (fadeSeconds * sampleRate).round().clamp(0, n ~/ 2);

    double phase = 0.0;

    for (int i = 0; i < n; i++) {
      final double t = i / (n - 1); // 0..1
      final double midi = midiStart + (midiEnd - midiStart) * t;
      final double freq = _midiToHz(midi);

      phase += 2.0 * pi * freq / sampleRate;
      double y = sin(phase) * amplitude;

      // Half-cosine fade in/out to prevent clicks
      if (fadeN > 0) {
        if (i < fadeN) {
          final u = i / (fadeN - 1);
          final env = 0.5 - 0.5 * cos(pi * u);
          y *= env;
        } else if (i >= n - fadeN) {
          final u = (n - 1 - i) / (fadeN - 1);
          final env = 0.5 - 0.5 * cos(pi * u);
          y *= env;
        }
      }

      out[i] = y;
    }
    return out;
  }

  /// Encode Float32List samples to WAV format (16-bit mono)
  Uint8List encodeWav16Mono(Float32List samples) {
    const int numChannels = 1;
    const int bitsPerSample = 16;
    const int bytesPerSample = bitsPerSample ~/ 8;

    final int dataBytes = samples.length * bytesPerSample;
    final int riffChunkSize = 36 + dataBytes;

    // WAV header (44 bytes)
    final header = ByteData(44);

    void writeAscii(int offset, String s) {
      for (int i = 0; i < s.length; i++) {
        header.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    header.setUint32(4, riffChunkSize, Endian.little);
    writeAscii(8, 'WAVE');

    writeAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little); // PCM fmt chunk size
    header.setUint16(20, 1, Endian.little); // audio format = PCM
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * numChannels * bytesPerSample,
        Endian.little); // byte rate
    header.setUint16(
        32, numChannels * bytesPerSample, Endian.little); // block align
    header.setUint16(34, bitsPerSample, Endian.little);

    writeAscii(36, 'data');
    header.setUint32(40, dataBytes, Endian.little);

    // PCM payload
    final pcm = Uint8List(dataBytes);
    final pcmBD = pcm.buffer.asByteData();

    for (int i = 0; i < samples.length; i++) {
      final double x = samples[i].clamp(-1.0, 1.0).toDouble();
      final int s16 = (x * 32767.0).round();
      pcmBD.setInt16(i * 2, s16, Endian.little);
    }

    final wav = Uint8List(44 + dataBytes);
    wav.setAll(0, header.buffer.asUint8List());
    wav.setAll(44, pcm);
    return wav;
  }

  /// Generate multiple consecutive sweeps and concatenate them.
  /// Each sweep is defined by (midiStart, midiEnd, durationSeconds).
  /// Returns concatenated samples with continuous phase.
  Float32List generateMultipleSweeps({
    required List<({double midiStart, double midiEnd, double durationSeconds})> sweeps,
    double amplitude = 0.2,
    double fadeSeconds = 0.01,
  }) {
    if (sweeps.isEmpty) {
      return Float32List(0);
    }

    final allSamples = <Float32List>[];
    double phase = 0.0; // Maintain phase continuity across sweeps

    for (var i = 0; i < sweeps.length; i++) {
      final sweep = sweeps[i];
      final samples = Float32List((sweep.durationSeconds * sampleRate).round());
      final int fadeN = (fadeSeconds * sampleRate).round().clamp(0, samples.length ~/ 2);

      for (int j = 0; j < samples.length; j++) {
        final double t = j / (samples.length - 1); // 0..1
        final double midi = sweep.midiStart + (sweep.midiEnd - sweep.midiStart) * t;
        final double freq = _midiToHz(midi);

        phase += 2.0 * pi * freq / sampleRate;
        double y = sin(phase) * amplitude;

        // Fade in at start of first sweep, fade out at end of last sweep
        // For middle sweeps, no fade to maintain continuity
        if (fadeN > 0) {
          if (i == 0 && j < fadeN) {
            // Fade in at start of first sweep
            final u = j / (fadeN - 1);
            final env = 0.5 - 0.5 * cos(pi * u);
            y *= env;
          } else if (i == sweeps.length - 1 && j >= samples.length - fadeN) {
            // Fade out at end of last sweep
            final u = (samples.length - 1 - j) / (fadeN - 1);
            final env = 0.5 - 0.5 * cos(pi * u);
            y *= env;
          }
        }

        samples[j] = y;
      }

      allSamples.add(samples);
    }

    // Concatenate all samples
    final totalLength = allSamples.fold<int>(0, (sum, samples) => sum + samples.length);
    final result = Float32List(totalLength);
    int offset = 0;
    for (final samples in allSamples) {
      result.setRange(offset, offset + samples.length, samples);
      offset += samples.length;
    }

    return result;
  }

  /// Generate a WAV file for multiple consecutive sweeps and return the file path
  Future<String> generateMultipleSweepsWav({
    required List<({double midiStart, double midiEnd, double durationSeconds})> sweeps,
    double amplitude = 0.2,
    double fadeSeconds = 0.01,
  }) async {
    final samples = generateMultipleSweeps(
      sweeps: sweeps,
      amplitude: amplitude,
      fadeSeconds: fadeSeconds,
    );

    final wavBytes = encodeWav16Mono(samples);
    final dir = await getTemporaryDirectory();
    final path = p.join(
        dir.path,
        'sine_sweeps_${DateTime.now().millisecondsSinceEpoch}.wav');
    final file = File(path);
    await file.writeAsBytes(wavBytes, flush: true);
    return file.path;
  }

  /// Generate a WAV file for a sine sweep and return the file path
  Future<String> generateSweepWav({
    required double midiStart,
    required double midiEnd,
    required double durationSeconds,
    double amplitude = 0.2,
    double fadeSeconds = 0.01,
  }) async {
    final samples = generateSineSweep(
      midiStart: midiStart,
      midiEnd: midiEnd,
      durationSeconds: durationSeconds,
      amplitude: amplitude,
      fadeSeconds: fadeSeconds,
    );

    final wavBytes = encodeWav16Mono(samples);
    final dir = await getTemporaryDirectory();
    final path = p.join(
        dir.path,
        'sine_sweep_${midiStart.toInt()}_${midiEnd.toInt()}_${DateTime.now().millisecondsSinceEpoch}.wav');
    final file = File(path);
    await file.writeAsBytes(wavBytes, flush: true);
    return file.path;
  }
}
