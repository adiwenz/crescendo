import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Runs WAV writing in an isolate to keep UI responsive.
Future<String> writeWavInIsolate({
  required List<double> samples,
  required int sampleRate,
  required String directoryPath,
}) async {
  return Isolate.run(() async {
    final out = List<double>.from(samples);

    final fadeSamples = math.min(out.length ~/ 2, (sampleRate * 0.008).round());
    if (fadeSamples > 0) {
      for (var i = 0; i < fadeSamples; i++) {
        final fadeIn = (i + 1) / fadeSamples;
        final fadeOut = (fadeSamples - i) / fadeSamples;
        out[i] *= fadeIn;
        out[out.length - 1 - i] *= fadeOut;
      }
    }

    double peak = 0.0;
    for (final s in out) {
      final a = s.abs();
      if (a > peak) peak = a;
    }
    const targetPeak = 0.95;
    if (peak > targetPeak && peak.isFinite && peak > 0) {
      final scale = targetPeak / peak;
      for (var i = 0; i < out.length; i++) {
        out[i] *= scale;
      }
    }

    final dataSize = out.length * 2;
    final bytes = ByteData(44 + dataSize);
    const channels = 1;
    bytes.setUint32(0, 0x52494646, Endian.big);
    bytes.setUint32(4, dataSize + 36, Endian.little);
    bytes.setUint32(8, 0x57415645, Endian.big);
    bytes.setUint32(12, 0x666d7420, Endian.big);
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, channels, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * channels * 2, Endian.little);
    bytes.setUint16(32, channels * 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    bytes.setUint32(36, 0x64617461, Endian.big);
    bytes.setUint32(40, dataSize, Endian.little);
    var offset = 44;
    for (final s in out) {
      final clamped = s.clamp(-1.0, 1.0);
      bytes.setInt16(offset, (clamped * 32767.0).round(), Endian.little);
      offset += 2;
    }
    final dir = Directory(directoryPath);
    await dir.create(recursive: true);
    final path = p.join(directoryPath, 'take_${DateTime.now().millisecondsSinceEpoch}.wav');
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return file.path;
  });
}
