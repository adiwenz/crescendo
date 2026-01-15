import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class SineSweepButton extends StatefulWidget {
  const SineSweepButton({super.key});

  @override
  State<SineSweepButton> createState() => _SineSweepButtonState();
}

class _SineSweepButtonState extends State<SineSweepButton> {
  final AudioPlayer _player = AudioPlayer();
  bool _busy = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  double _midiToHz(double midi) => 440.0 * pow(2.0, (midi - 69.0) / 12.0);

  /// MIDI-like sweep: linear in semitone space, continuous phase accumulation.
  Float32List _generateSineSweep({
    required double midiStart,
    required double midiEnd,
    required double durationSeconds,
    required int sampleRate,
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

  Uint8List _encodeWav16Mono(Float32List samples, int sampleRate) {
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

  Future<File> _writeTempWav(Uint8List wavBytes,
      {String name = 'sine_sweep.wav'}) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(wavBytes, flush: true);
    return file;
  }

  Future<void> _playSweep() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      const sr = 48000;
      const dur = 3.0;

      // G3 -> C5
      const midiStart = 55.0;
      const midiEnd = 72.0;

      final samples = _generateSineSweep(
        midiStart: midiStart,
        midiEnd: midiEnd,
        durationSeconds: dur,
        sampleRate: sr,
        amplitude: 0.2,
        fadeSeconds: 0.01,
      );

      final wavBytes = _encodeWav16Mono(samples, sr);
      final file = await _writeTempWav(wavBytes, name: 'sine_sweep_g3_c5.wav');

      // Stop any current playback cleanly
      await _player.stop();

      // Play the file
      await _player.play(DeviceFileSource(file.path));
    } catch (e) {
      debugPrint('Sine sweep playback failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sine sweep playback failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _busy ? null : _playSweep,
      icon: const Icon(Icons.play_arrow),
      label: Text(_busy ? 'Preparing…' : 'Play Sine Sweep (G3 → C5)'),
    );
  }
}
