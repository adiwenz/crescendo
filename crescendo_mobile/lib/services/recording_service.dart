import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';

import '../models/pitch_frame.dart';
import 'pitch_detection_service.dart';

class RecordingResult {
  final String audioPath;
  final List<PitchFrame> frames;

  RecordingResult(this.audioPath, this.frames);
}

class RecordingService {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  StreamController<Uint8List>? _recorderController;
  final PitchDetectionService pitchDetection;
  final int sampleRate;
  final int frameSize;
  final int hopSize;

  final _samples = <double>[];
  final _streamFrames = <PitchFrame>[];
  final _buffer = <double>[];
  final StreamController<PitchFrame> _liveController =
      StreamController<PitchFrame>.broadcast();
  StreamSubscription<Uint8List>? _recorderSub;
  bool _initialized = false;
  bool _isRecording = false;
  bool _isStopping = false;
  bool _streaming = false;
  double _streamTime = 0.0;

  // Buffer-boundary click reduction.
  static const int _joinFadeSamples = 32; // ~0.7ms @ 44.1k
  static const double _joinJumpThreshold = 0.04; // in [-1,1] float domain

  RecordingService({
    this.sampleRate = 44100,
    this.frameSize = 1024,
    this.hopSize = 64,
    PitchDetectionService? pitchDetection,
  }) : pitchDetection = pitchDetection ??
            PitchDetectionService(
                sampleRate: sampleRate, frameSize: frameSize, hopSize: hopSize);

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await _recorder.openRecorder();
    await _recorder.setSubscriptionDuration(const Duration(milliseconds: 20));
    _initialized = true;
  }

  Future<void> start() async {
    final status = await Permission.microphone.request();
    // if (!status.isGranted) {
    //   // ignore: avoid_print
    //   print('[recording] microphone permission status=$status');
    //   if (status.isPermanentlyDenied) {
    //     throw StateError(
    //         'Microphone permission permanently denied. Enable it in Settings > Privacy & Security > Microphone.');
    //   }
    //   throw StateError('Microphone permission not granted (status=$status).');
    // }
    await _ensureInit();
    _samples.clear();
    _streamFrames.clear();
    _buffer.clear();
    _streamTime = 0.0;
    await _recorderSub?.cancel();
    await _recorderController?.close();
    _recorderController = StreamController<Uint8List>();
    _isRecording = true;
    _streaming = true;
    final detector = PitchDetector(
        audioSampleRate: sampleRate.toDouble(), bufferSize: frameSize);
    _recorderSub = _recorderController!.stream.listen((data) {
      final pcmData = _extractPcmData(data);
      if (pcmData.isEmpty) return;
      final buffer = _pcm16BytesToDoubles(pcmData);
      _appendWithBoundarySmoothing(buffer);
      while (_buffer.length >= frameSize) {
        final frame = List<double>.from(_buffer.take(frameSize));
        final currentTime = _streamTime;
        detector.getPitchFromFloatBuffer(frame).then((result) {
          final hzVal = result.pitch;
          final hz = hzVal != null && hzVal > 0 ? hzVal.toDouble() : null;
          final midi = hz != null && hz > 0
              ? 69 + 12 * (math.log(hz / 440) / math.ln2)
              : null;
          final pf = PitchFrame(time: currentTime, hz: hz, midi: midi);
          _streamFrames.add(pf);
          _liveController.add(pf);
        });
        _buffer.removeRange(0, hopSize);
        _streamTime += hopSize / sampleRate;
      }
    });

    await _recorder.startRecorder(
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: sampleRate,
      toStream: _recorderController!.sink,
    );
  }

  Future<RecordingResult> stop() async {
    if (!_isRecording || _isStopping) return RecordingResult('', const []);
    _isStopping = true;
    try {
      if (_streaming) {
        try {
          await _recorder.stopRecorder();
        } catch (_) {
          // ignore if plugin reports no active stream
        }
      }
      _streaming = false;
      await _recorderSub?.cancel();
      _recorderSub = null;
      await _recorderController?.close();
      _recorderController = null;
      final frames = _streamFrames.isNotEmpty
          ? List<PitchFrame>.from(_streamFrames)
          : await pitchDetection.offlineFromSamples(_samples);
      // ignore: avoid_print
      print('[recording] writing wav... samples=${_samples.length}');
      final wavPath = await _writeWav(_samples);

      // Print the raw path on its own line for easy copy/paste.
      // ignore: avoid_print
      print(wavPath);

      // Log where the WAV was written so we can inspect it on the simulator.
      try {
        final f = File(wavPath);
        final len = await f.length();
        // ignore: avoid_print
        print('[recording] saved_wav_path=$wavPath bytes=$len');
      } catch (_) {
        // ignore: avoid_print
        print('[recording] saved_wav_path=$wavPath');
      }

      return RecordingResult(wavPath, frames);
    } finally {
      // ignore: avoid_print
      print('[recording] stop() finished');
      _isRecording = false;
      _isStopping = false;
    }
  }

  Stream<PitchFrame> get liveStream => _liveController.stream;

  Uint8List _extractPcmData(Uint8List data) => data;

  List<double> _pcm16BytesToDoubles(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    final out = <double>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final v = bd.getInt16(i, Endian.little);
      out.add(v / 32768.0);
    }
    return out;
  }

  void _appendWithBoundarySmoothing(List<double> buffer) {
    if (buffer.isEmpty) return;

    if (_samples.isNotEmpty) {
      final last = _samples.last;
      final first = buffer.first;
      final jump = (first - last).abs();

      if (jump > _joinJumpThreshold && jump.isFinite) {
        final n = _joinFadeSamples;
        for (var i = 1; i <= n; i++) {
          final t = i / (n + 1);
          final v = last + (first - last) * t;
          _samples.add(v);
          _buffer.add(v);
        }
      }
    }

    _samples.addAll(buffer);
    _buffer.addAll(buffer);
  }

  Future<String> _writeWav(List<double> samples) async {
    // Copy-on-write: never mutate the caller's buffer (e.g. `_samples`).
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
      // ignore: avoid_print
      print(
          '[AudioDiag] writeWav scaled down: peak=${peak.toStringAsFixed(4)} -> ${targetPeak.toStringAsFixed(2)} (scale=${scale.toStringAsFixed(4)})');
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
    final dir = await getApplicationDocumentsDirectory();
    await dir.create(recursive: true);
    final path =
        p.join(dir.path, 'take_${DateTime.now().millisecondsSinceEpoch}.wav');
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    // ignore: avoid_print
    print('[recording] wrote_wav=$path');
    await _debugReadbackWav(path);
    return file.path;
  }

  Future<void> _debugReadbackWav(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.length < 44) return;
      final bd = ByteData.sublistView(bytes);
      final sr = bd.getUint32(24, Endian.little);
      final ch = bd.getUint16(22, Endian.little);
      final bps = bd.getUint16(34, Endian.little);
      final dataSize = bd.getUint32(40, Endian.little);
      const dataOffset = 44;
      final totalSamples = (dataOffset + dataSize) <= bytes.length
          ? dataSize ~/ 2
          : ((bytes.length - dataOffset) ~/ 2);

      int peak = 0;
      int nearFull = 0;
      int clipped = 0;

      for (var i = 0; i < totalSamples; i++) {
        final v = bd.getInt16(dataOffset + i * 2, Endian.little);
        final a = v.abs();
        if (a > peak) peak = a;
        if (a >= 32760) nearFull++;
        if (a >= 32767) clipped++;
      }

      // ignore: avoid_print
      print(
          '[WAV_READBACK] sr=$sr ch=$ch bps=$bps dataSize=$dataSize totalSamples=$totalSamples peak=$peak nearFull=$nearFull clipped=$clipped path=$path');
    } catch (_) {
      // ignore
    }
  }
}
