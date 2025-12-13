import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_audio_capture/flutter_audio_capture.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';
import 'dart:math' as math;
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
  final _streamFrames = <PitchFrame>[];
  final _buffer = <double>[];
  final StreamController<PitchFrame> _liveController = StreamController<PitchFrame>.broadcast();
  StreamSubscription? _sub;
  bool _initialized = false;
  double _streamTime = 0.0;

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
    _streamFrames.clear();
    _buffer.clear();
    _streamTime = 0.0;
    _sub?.cancel();
    _sub = null;
    final detector = PitchDetector(audioSampleRate: sampleRate.toDouble(), bufferSize: frameSize);
    await _capture.start(
      (obj) {
        final buffer = obj as List<double>;
        _samples.addAll(buffer);
        _buffer.addAll(buffer);
        while (_buffer.length >= frameSize) {
          final frame = List<double>.from(_buffer.take(frameSize));
          final currentTime = _streamTime;
          detector.getPitchFromFloatBuffer(frame).then((result) {
            final hzVal = result.pitch;
            final hz = hzVal != null && hzVal > 0 ? hzVal.toDouble() : null;
            final midi = hz != null && hz > 0 ? 69 + 12 * (math.log(hz / 440) / math.ln2) : null;
            final pf = PitchFrame(time: currentTime, hz: hz, midi: midi);
            _streamFrames.add(pf);
            _liveController.add(pf);
          });
          _buffer.removeRange(0, hopSize);
          _streamTime += hopSize / sampleRate;
        }
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
    final frames = _streamFrames.isNotEmpty ? List<PitchFrame>.from(_streamFrames) : await pitchDetection.offlineFromSamples(_samples);
    final wavPath = await _writeWav(_samples);
    return RecordingResult(wavPath, frames);
  }

  Stream<PitchFrame> get liveStream => _liveController.stream;

  Future<String> _writeWav(List<double> samples) async {
    final fadeSamples = math.min(samples.length ~/ 2, (sampleRate * 0.005).round());
    for (var i = 0; i < fadeSamples; i++) {
      final gain = i / fadeSamples;
      samples[i] *= gain;
      samples[samples.length - 1 - i] *= gain;
    }

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
