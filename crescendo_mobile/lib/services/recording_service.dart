import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../audio/recording_analysis.dart';

import '../models/pitch_frame.dart';
import 'pitch_detection_service.dart';

class RecordingResult {
  final String audioPath;
  final List<PitchFrame> frames;
  final Future<String>? wavFuture;

  RecordingResult(this.audioPath, this.frames, {this.wavFuture});
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
  final StreamController<PitchFrame> _liveController =
      StreamController<PitchFrame>.broadcast();
  StreamController<List<double>>? _pcmController;
  StreamSubscription<Uint8List>? _recorderSub;
  StreamSubscription? _onProgressSub;
  StreamSubscription<PitchData>? _pitchSub;
  Stopwatch? _pitchWatch;
  bool _initialized = false;
  bool _isRecording = false;
  bool _isStopping = false;
  bool _streaming = false;
  double _streamTime = 0.0;

  RecordingService({
    this.sampleRate = 44100,
    this.frameSize = 1024,
    this.hopSize = 64,
    PitchDetectionService? pitchDetection,
  }) : pitchDetection = pitchDetection ?? PitchDetectionService();

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await _recorder.openRecorder();
    await _recorder.setSubscriptionDuration(const Duration(milliseconds: 20));
    _initialized = true;
  }

  Future<void> start() async {
    final status = await Permission.microphone.request();
    await _ensureInit();
    _pitchWatch = Stopwatch()..start();
    await _pitchSub?.cancel();
    _onProgressSub?.cancel();
    _samples.clear();
    _streamFrames.clear();
    _streamTime = 0.0;
    await _recorderSub?.cancel();
    await _recorderController?.close();
    await _pcmController?.close();
    _pcmController = StreamController<List<double>>.broadcast();
    _recorderController = StreamController<Uint8List>();
    _isRecording = true;
    _streaming = true;
    _pitchSub = pitchDetection.pitchStream.listen((pd) {
      final elapsedSec = (_pitchWatch?.elapsedMilliseconds ?? 0) / 1000.0;
      final midi = 69 + 12 * (math.log(pd.frequency / 440.0) / math.ln2);
      final pf = PitchFrame(
        time: elapsedSec,
        hz: pd.frequency,
        midi: midi,
        centsError: pd.cents,
      );
      _streamFrames.add(pf);
      _liveController.add(pf);
    });
    await pitchDetection.start(sampleRate: sampleRate, bufferSize: frameSize);
    _recorderSub = _recorderController!.stream.listen((data) {
      final pcmData = _extractPcmData(data);
      if (pcmData.isEmpty) return;
      final buffer = _pcm16BytesToDoubles(pcmData);
      _pcmController?.add(buffer);
      _samples.addAll(buffer);
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
    final sw = Stopwatch()..start();
    // ignore: avoid_print
    print('[recording] stop pressed t=${DateTime.now().toIso8601String()}');
    _isStopping = true;
    try {
      await pitchDetection.stop();
      await _pitchSub?.cancel();
      _pitchSub = null;
      _pitchWatch?.stop();
      await _recorderSub?.cancel();
      _recorderSub = null;
      await _onProgressSub?.cancel();
      _onProgressSub = null;
      // ignore: avoid_print
      print('[recording] streams canceled (${sw.elapsedMilliseconds}ms)');
      if (_streaming) {
        try {
          await _recorder.stopRecorder();
          // ignore: avoid_print
          print('[recording] stopRecorder done (${sw.elapsedMilliseconds}ms)');
        } catch (_) {
          // ignore if plugin reports no active stream
        }
      }
      _streaming = false;
      await _recorderController?.close();
      _recorderController = null;
      // ignore: avoid_print
      print('[recording] controller closed (${sw.elapsedMilliseconds}ms)');
      final frames = _streamFrames.isNotEmpty
          ? List<PitchFrame>.from(_streamFrames)
          : const <PitchFrame>[];

      final samplesCopy = List<double>.from(_samples);
      final wavFuture = _writeWavIsolate(samplesCopy);
      wavFuture.then((path) {
        // ignore: avoid_print
        print('[recording] post-processing finished (${sw.elapsedMilliseconds}ms) path=$path');
      });
      // ignore: avoid_print
      print('[recording] stop returning (${sw.elapsedMilliseconds}ms)');
      return RecordingResult('', frames, wavFuture: wavFuture);
    } finally {
      // ignore: avoid_print
      print('[recording] stop() finished');
      _isRecording = false;
      _isStopping = false;
    }
  }

  Stream<PitchFrame> get liveStream => _liveController.stream;
  Stream<List<double>> get rawPcmStream =>
      _pcmController?.stream ?? const Stream.empty();

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

  Future<String> _writeWavIsolate(List<double> samples) {
    return getApplicationDocumentsDirectory().then(
      (dir) => writeWavInIsolate(
        samples: samples,
        sampleRate: sampleRate,
        directoryPath: dir.path,
      ),
    );
  }
}
