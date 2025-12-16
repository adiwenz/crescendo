import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../audio/wav_writer.dart';
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

  final _samples = <double>[];
  final _frames = <PitchFrame>[];
  final StreamController<PitchFrame> _liveController =
      StreamController<PitchFrame>.broadcast();
  StreamController<List<double>>? _pcmController;
  StreamSubscription<Uint8List>? _sub;
  bool _isRecording = false;
  double _timeCursor = 0;

  RecordingService({this.sampleRate = 44100});

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

    _sub = stream.listen((data) {
      final buf = _pcm16BytesToDoubles(data);
      _pcmController?.add(buf);
      _samples.addAll(buf);
      final dt = buf.isEmpty ? 0.0 : buf.length / sampleRate;
      _timeCursor += dt;
      final pf = PitchFrame(time: _timeCursor);
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
    final intSamples =
        _samples.map((s) => (s.clamp(-1.0, 1.0) * 32767).round()).toList();
    await WavWriter.writePcm16Mono(
      samples: intSamples,
      sampleRate: sampleRate,
      path: path,
    );

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
