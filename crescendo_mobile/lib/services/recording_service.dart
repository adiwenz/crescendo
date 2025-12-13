import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_audio_capture/flutter_audio_capture.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/pitch_frame.dart';
import 'pitch_detection_service.dart';

class RecordingResult {
  final String audioPath;
  final List<PitchFrame> frames;

  RecordingResult(this.audioPath, this.frames);
}

class RecordingService {
  final FlutterAudioCapture _capture = FlutterAudioCapture();
  final PitchDetectionService pitchDetection;
  final int sampleRate;
  final int frameSize;
  final int hopSize;

  final _samples = <double>[];
  StreamSubscription? _sub;
  bool _initialized = false;

  RecordingService({
    this.sampleRate = 44100,
    this.frameSize = 2048,
    this.hopSize = 256,
    PitchDetectionService? pitchDetection,
  }) : pitchDetection = pitchDetection ?? PitchDetectionService(sampleRate: 44100, frameSize: 2048, hopSize: 256);

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await _capture.init();
    _initialized = true;
  }

  Future<void> start() async {
    await _ensureInit();
    _samples.clear();
    _sub?.cancel();
    _sub = null;
    await _capture.start(
      (obj) {
        final buffer = obj as List<double>;
        _samples.addAll(buffer);
      },
      (err) {},
      sampleRate: sampleRate,
      bufferSize: frameSize,
    );
  }

  Future<RecordingResult> stop() async {
    await _capture.stop();
    _sub?.cancel();
    _sub = null;
    final frames = await pitchDetection.offlineFromSamples(_samples);
    final wavPath = await _writeWav(_samples);
    return RecordingResult(wavPath, frames);
  }

  Future<String> _writeWav(List<double> samples) async {
    final dataSize = samples.length * 2;
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
    for (final s in samples) {
      bytes.setInt16(offset, (s.clamp(-1.0, 1.0) * 32767).toInt(), Endian.little);
      offset += 2;
    }
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'take_${DateTime.now().millisecondsSinceEpoch}.wav');
    final file = File(path);
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return file.path;
  }
}
