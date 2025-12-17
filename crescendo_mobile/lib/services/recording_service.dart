import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';
import 'package:wav/wav.dart';

import '../models/pitch_frame.dart';

class RecordingResult {
  final String audioPath;
  final List<PitchFrame> frames;

  RecordingResult(this.audioPath, this.frames);
}

/// Thin wrapper around [AudioRecorder] that exposes PCM stream + simple frames.
class RecordingService {
  final AudioRecorder _recorder = AudioRecorder();
  final int sampleRate;
  final int bufferSize;

  final PitchDetector _pitchDetector;
  final _samples = <double>[];
  final _pitchBuffer = <double>[];
  final _frames = <PitchFrame>[];
  final StreamController<PitchFrame> _liveController =
      StreamController<PitchFrame>.broadcast();
  StreamController<List<double>>? _pcmController;
  StreamSubscription<Uint8List>? _sub;
  bool _isRecording = false;
  double _timeCursor = 0;

  RecordingService({this.sampleRate = 44100, this.bufferSize = 2048})
      : _pitchDetector =
            PitchDetector(audioSampleRate: sampleRate.toDouble(), bufferSize: bufferSize);

  Stream<PitchFrame> get liveStream => _liveController.stream;
  Stream<List<double>> get rawPcmStream =>
      _pcmController?.stream ?? const Stream.empty();

  Future<void> start() async {
    if (_isRecording) return;
    if (!await _recorder.hasPermission()) {
      // ignore: avoid_print
      print('[recording] mic permission denied');
      return;
    }
    _samples.clear();
    _pitchBuffer.clear();
    _frames.clear();
    _timeCursor = 0;
    await _pcmController?.close();
    _pcmController = StreamController<List<double>>.broadcast();
    _isRecording = true;

    final stream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
      ),
    );

    _sub = stream.listen((data) async {
      final buf = _pcm16BytesToDoubles(data);
      _pcmController?.add(buf);
      _samples.addAll(buf);
      _pitchBuffer.addAll(buf);
      // keep pitch buffer bounded
      if (_pitchBuffer.length > bufferSize * 4) {
        _pitchBuffer.removeRange(0, _pitchBuffer.length - bufferSize * 2);
      }
      final dt = buf.isEmpty ? 0.0 : buf.length / sampleRate;
      _timeCursor += dt;
      double? hz;
      double? midi;
      try {
        if (_pitchBuffer.length >= bufferSize) {
          final window =
              _pitchBuffer.sublist(_pitchBuffer.length - bufferSize);
          final res = await _pitchDetector.getPitchFromFloatBuffer(window);
          if (res.pitched && res.pitch.isFinite && res.pitch > 0) {
            hz = res.pitch;
            midi = 69 + 12 * (math.log(hz / 440.0) / math.ln2);
          }
        }
      } catch (_) {
        // ignore pitch detection errors
      }
      final pf = PitchFrame(time: _timeCursor, hz: hz, midi: midi);
      _frames.add(pf);
      _liveController.add(pf);
    });
  }

  Future<RecordingResult> stop() async {
    if (!_isRecording) return RecordingResult('', const []);
    await _sub?.cancel();
    _sub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    _isRecording = false;

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'take_${DateTime.now().millisecondsSinceEpoch}.wav');
    final floats = Float64List.fromList(_samples);
    final wav = Wav([floats], sampleRate, WavFormat.pcm16bit);
    final bytes = wav.write();
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);

    return RecordingResult(path, List<PitchFrame>.from(_frames));
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _pcmController?.close();
    await _liveController.close();
    await _recorder.dispose();
  }

  List<double> _pcm16BytesToDoubles(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    final out = <double>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final v = bd.getInt16(i, Endian.little);
      out.add(v / 32768.0);
    }
    return out;
  }
}
