import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';
import 'package:wav/wav.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/pitch_frame.dart';
import 'audio_session_manager.dart';

class RecordingResult {
  final String audioPath;
  final List<PitchFrame> frames;

  RecordingResult(this.audioPath, this.frames);
}

/// Thin wrapper around [AudioRecorder] that exposes PCM stream + simple frames.
/// Coordinates with AudioSessionManager to prevent microphone conflicts.
class RecordingService {
  final AudioSessionManager _sessionManager = AudioSessionManager.instance;
  final String _owner; // 'piano' or 'exercise'
  final int sampleRate;
  final int bufferSize;
  final AudioRecorder _recorder = AudioRecorder();

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

  RecordingService({
    this.sampleRate = 44100,
    this.bufferSize = 1024, // Smaller buffer for lower latency (~23ms at 44.1kHz)
    String owner = 'exercise', // Default to 'exercise', Piano will use 'piano'
  })  : _owner = owner,
        _pitchDetector =
            PitchDetector(audioSampleRate: sampleRate.toDouble(), bufferSize: bufferSize);

  Stream<PitchFrame> get liveStream => _liveController.stream;
  Stream<List<double>> get rawPcmStream =>
      _pcmController?.stream ?? const Stream.empty();

  Future<void> start() async {
    if (_isRecording) {
      debugPrint('[RecordingService] Already recording (owner: $_owner), skipping start. Current state: _isRecording=true');
      return;
    }

    // Request access from session manager
    final requestStartTime = DateTime.now();
    debugPrint('[RecordingService] Requesting access for $_owner at ${requestStartTime.millisecondsSinceEpoch}');
    final accessGranted = await _sessionManager.requestAccess(_owner);
    final requestEndTime = DateTime.now();
    debugPrint('[RecordingService] Access request took ${requestEndTime.difference(requestStartTime).inMilliseconds}ms, granted: $accessGranted');
    if (!accessGranted) {
      debugPrint('[RecordingService] Failed to get microphone access (owner: $_owner)');
      // Force release and retry once
      await _sessionManager.forceReleaseAll();
      await Future.delayed(const Duration(milliseconds: 300));
      final retryGranted = await _sessionManager.requestAccess(_owner);
      if (!retryGranted) {
        debugPrint('[RecordingService] Retry failed, cannot start recording');
        return;
      }
    }

    debugPrint('[RecordingService] Starting recording (owner: $_owner)...');
    debugPrint('[RecordingService] Mic started - reason: normal start');
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

  Future<RecordingResult> stop({String? customPath}) async {
    if (!_isRecording) return RecordingResult('', const []);
    debugPrint('[RecordingService] Stopping recording (owner: $_owner)...');
    debugPrint('[RecordingService] Mic stopped - reason: normal stop');
    await _sub?.cancel();
    _sub = null;
    try {
      await _recorder.stop();
      debugPrint('[RecordingService] Recorder stopped');
    } catch (e) {
      debugPrint('[RecordingService] Error stopping recorder: $e');
    }
    _isRecording = false;
    
    // Release access from session manager
    await _sessionManager.releaseAccess(_owner);
    debugPrint('[RecordingService] Released microphone access');

    final dir = await getApplicationDocumentsDirectory();
    final path = customPath ?? p.join(dir.path, 'take_${DateTime.now().millisecondsSinceEpoch}.wav');
    final floats = Float64List.fromList(_samples);
    final wav = Wav([floats], sampleRate, WavFormat.pcm16bit);
    final bytes = wav.write();
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);

    return RecordingResult(path, List<PitchFrame>.from(_frames));
  }

  Future<void> dispose() async {
    debugPrint('[RecordingService] Disposing (owner: $_owner)...');
    if (_isRecording) {
      try {
        await stop();
      } catch (e) {
        debugPrint('[RecordingService] Error stopping during dispose: $e');
      }
    }
    await _sub?.cancel();
    _sub = null;
    await _pcmController?.close();
    _pcmController = null;
    await _liveController.close();
    
    // Force release access if still held
    await _sessionManager.releaseAccess(_owner, force: true);
    debugPrint('[RecordingService] Disposed and released access');
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
