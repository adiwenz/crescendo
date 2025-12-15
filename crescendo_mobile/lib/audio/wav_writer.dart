import 'dart:io';
import 'dart:typed_data';

/// Minimal WAV writer for mono 16-bit PCM files.
class WavWriter {
  static Future<void> writePcm16Mono({
    required List<int> samples,
    required int sampleRate,
    required String path,
  }) async {
    final clamped = List<int>.generate(samples.length, (i) {
      final v = samples[i];
      if (v > 32767) return 32767;
      if (v < -32768) return -32768;
      return v;
    });

    final dataSize = clamped.length * 2;
    final bytes = ByteData(44 + dataSize);
    const channels = 1;

    // RIFF header.
    bytes.setUint32(0, 0x52494646, Endian.big); // "RIFF"
    bytes.setUint32(4, dataSize + 36, Endian.little);
    bytes.setUint32(8, 0x57415645, Endian.big); // "WAVE"

    // fmt chunk.
    bytes.setUint32(12, 0x666d7420, Endian.big); // "fmt "
    bytes.setUint32(16, 16, Endian.little); // PCM header size
    bytes.setUint16(20, 1, Endian.little); // PCM format
    bytes.setUint16(22, channels, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * channels * 2, Endian.little); // byte rate
    bytes.setUint16(32, channels * 2, Endian.little); // block align
    bytes.setUint16(34, 16, Endian.little); // bits per sample

    // data chunk.
    bytes.setUint32(36, 0x64617461, Endian.big); // "data"
    bytes.setUint32(40, dataSize, Endian.little);
    var offset = 44;
    for (final v in clamped) {
      bytes.setInt16(offset, v, Endian.little);
      offset += 2;
    }

    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  }

  /// Quick readback of key WAV metadata for debugging.
  static Future<Map<String, Object>> debugReadbackPcm16(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return const {};
      final bytes = await file.readAsBytes();
      if (bytes.length < 44) return const {};
      final bd = ByteData.sublistView(bytes);
      final sampleRate = bd.getUint32(24, Endian.little);
      final channels = bd.getUint16(22, Endian.little);
      final bitsPerSample = bd.getUint16(34, Endian.little);
      final declaredDataSize = bd.getUint32(40, Endian.little);
      const dataOffset = 44;
      final availableData = bytes.length >= dataOffset
          ? bytes.length - dataOffset
          : 0;
      final dataSize = declaredDataSize <= availableData
          ? declaredDataSize
          : availableData;
      final totalSamples = dataSize ~/ 2;

      int peakAbsInt16 = 0;
      int nearFullScaleCount = 0;
      for (var i = 0; i < totalSamples; i++) {
        final v = bd.getInt16(dataOffset + i * 2, Endian.little);
        final a = v.abs();
        if (a > peakAbsInt16) peakAbsInt16 = a;
        if (a >= 32760) nearFullScaleCount++;
      }

      return {
        'sampleRate': sampleRate,
        'channels': channels,
        'bitsPerSample': bitsPerSample,
        'dataSize': dataSize,
        'totalSamples': totalSamples,
        'peakAbsInt16': peakAbsInt16,
        'nearFullScaleCount': nearFullScaleCount,
      };
    } catch (_) {
      return const {};
    }
  }
}
