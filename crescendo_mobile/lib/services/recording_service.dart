import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';
import 'package:wav/wav.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, compute;

import 'dart:isolate';
import '../models/pitch_frame.dart';
import '../utils/audio_constants.dart';
import 'audio_session_manager.dart';

enum RecordingMode {
  /// Ephemeral mode for live feedback (Piano screen). No WAV encoding, no file IO.
  live,
  /// Persistent mode for user takes (Exercises). Performs WAV encoding and IO.
  take,
}

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

  final _frames = <PitchFrame>[];
  final StreamController<PitchFrame> _liveController =
      StreamController<PitchFrame>.broadcast();
  StreamController<List<double>>? _pcmController;
  StreamSubscription<Uint8List>? _sub;
  bool _isRecording = false;
  RecordingMode _currentMode = RecordingMode.take;
  double _timeCursor = 0;

  // Isolate-based worker
  Isolate? _workerIsolate;
  SendPort? _workerSendPort;
  ReceivePort? _workerReceivePort;
  Completer<void>? _workerReady;
  Completer<void>? _stopCompleter;
  String? _tempPcmPath;
  String? _activeOwner; // Safety guard to ensure only the visible owner runs

  RecordingService({
    this.sampleRate = AudioConstants.audioSampleRate,
    this.bufferSize = 1024, // Smaller buffer for lower latency (~21ms at 48kHz)
    String owner = 'exercise', // Default to 'exercise', Piano will use 'piano'
  })  : _owner = owner;

  Stream<PitchFrame> get liveStream => _liveController.stream;
  Stream<List<double>> get rawPcmStream =>
      _pcmController?.stream ?? const Stream.empty();

  Future<void> start({required String owner, RecordingMode mode = RecordingMode.take}) async {
    if (_isRecording) {
      if (_activeOwner == owner) {
        debugPrint('[RecordingService] Already recording for $owner, skipping start.');
        return;
      } else {
        debugPrint('[RecordingService] Takeover: stopping current recording for $_activeOwner to start for $owner');
        await stop();
      }
    }

    _activeOwner = owner;

    // Pre-launch worker isolate
    await _ensureWorker();

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

    debugPrint('[RecordingService] Starting recording (owner: $_owner, mode: ${mode.name})...');
    debugPrint('[RecordingService] Mic started - reason: normal start');
    _currentMode = mode;
    _frames.clear();
    _timeCursor = 0;
    
    // Prepare temp PCM path if in take mode
    if (_currentMode == RecordingMode.take) {
      final dir = await getTemporaryDirectory();
      _tempPcmPath = p.join(dir.path, 'raw_recording_${DateTime.now().millisecondsSinceEpoch}.pcm');
    } else {
      _tempPcmPath = null;
    }

    // Configure worker
    _workerSendPort?.send(_WorkerConfig(
      owner: _owner,
      sampleRate: sampleRate,
      bufferSize: bufferSize,
      pcmPath: _tempPcmPath,
    ));

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

    if (kDebugMode) {
      debugPrint('[RecordingService] Requested rate: $sampleRate');
    }

    int chunkCount = 0;
    _sub = stream.listen((Uint8List data) {
      if (!_isRecording) return;
      // Offload EVERYTHING to worker
      _workerSendPort?.send(data);
      
      // Periodically log for instrumentation (UI isolate side)
      chunkCount++;
      if (chunkCount % 100 == 0) {
        debugPrint('[RecordingService] ($_owner) Streamed chunk #$chunkCount: ${data.length} bytes');
      }
    });
  }

  Future<void> _ensureWorker() async {
    if (_workerIsolate != null) return;
    
    debugPrint('[RecordingService] Launching worker isolate...');
    _workerReady = Completer<void>();
    _workerReceivePort = ReceivePort();
    
    _workerIsolate = await Isolate.spawn(_RecordingWorker.entryPoint, _workerReceivePort!.sendPort);
    
    // First message from worker is its SendPort
    _workerReceivePort!.listen((message) {
      if (message is SendPort) {
        debugPrint('[RecordingService] Worker SendPort received');
        _workerSendPort = message;
        _workerReady?.complete();
      } else if (message is PitchFrame) {
        if (_frames.isEmpty) debugPrint('[RecordingService] FIRST PITCH FRAME from worker: hz=${message.hz}');
        _frames.add(message);
        _liveController.add(message);
      } else if (message == 'done') {
        debugPrint('[RecordingService] Worker cleanup done');
        _stopCompleter?.complete();
      } else {
        debugPrint('[RecordingService] Unknown message from worker: $message');
      }
    });
    
    await _workerReady?.future;
    debugPrint('[RecordingService] Worker isolate ready');
  }

  Future<RecordingResult?> stop({String? customPath}) async {
    if (!_isRecording) {
      _activeOwner = null;
      return null;
    }
    
    final currentOwner = _activeOwner ?? _owner;
    debugPrint('[RecordingService] ($currentOwner) Mic stopping - reason: normal stop');
    _isRecording = false; // Block further sends to worker immediately
    _activeOwner = null;
    
    await _sub?.cancel();
    _sub = null;
    
    debugPrint('[RecordingService] ($_owner) Awaiting worker cleanup...');
    
    // Stop worker processing (flushes file)
    _stopCompleter = Completer<void>();
    _workerSendPort?.send('stop');
    await _stopCompleter?.future;
    
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

    if (_currentMode == RecordingMode.live) {
      debugPrint('[RecordingService] Live mode: skipping WAV writing and returning null');
      final result = RecordingResult('', List<PitchFrame>.from(_frames));
      _frames.clear();
      return result;
    }

    final dir = await getApplicationDocumentsDirectory();
    final path = customPath ?? p.join(dir.path, 'take_${DateTime.now().millisecondsSinceEpoch}.wav');
    
    // Performance Trace: Offloading WAV encoding & IO to background
    debugPrint('[RecordingService] Offloading WAV encoding from PCM file to background for $path');
    final startTime = DateTime.now();
    
    await compute(_writeWavFromPcm, {
      'path': path,
      'pcmPath': _tempPcmPath,
      'sampleRate': sampleRate,
    });

    final elapsed = DateTime.now().difference(startTime);
    debugPrint('[RecordingService] Finished WAV writing in ${elapsed.inMilliseconds}ms');

    return RecordingResult(path, List<PitchFrame>.from(_frames));
  }

  /// Background isolate worker for encoding and writing WAV from PCM file
  static Future<void> _writeWavFromPcm(Map<String, dynamic> params) async {
    final path = params['path'] as String;
    final pcmPath = params['pcmPath'] as String?;
    final sampleRate = params['sampleRate'] as int;

    if (pcmPath == null) return;
    
    final pcmFile = File(pcmPath);
    if (!await pcmFile.exists()) return;
    
    final bytes = await pcmFile.readAsBytes();
    final samples = _pcm16BytesToDoublesStatic(bytes);
    final floats = Float64List.fromList(samples);

    final wav = Wav([floats], sampleRate, WavFormat.pcm16bit);
    final wavBytes = wav.write();
    
    final file = File(path);
    final tempPath = '$path.tmp';
    final tempFile = File(tempPath);
    
    await tempFile.parent.create(recursive: true);
    await tempFile.writeAsBytes(wavBytes, flush: true);
    
    // Atomic rename to ensure file is complete before visibility
    if (await file.exists()) await file.delete();
    await tempFile.rename(path);
    
    // Cleanup temp PCM
    // Cleanup temp PCM
    try {
      await pcmFile.delete();
    } catch (_) {}
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
    
    // Kill worker
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _workerReceivePort?.close();
    
    await _pcmController?.close();
    _pcmController = null;
    await _liveController.close();
    
    // Force release access if still held
    await _sessionManager.releaseAccess(_owner, force: true);
    debugPrint('[RecordingService] Disposed and released access');
  }

  static List<double> _pcm16BytesToDoublesStatic(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    final out = <double>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final v = bd.getInt16(i, Endian.little);
      out.add(v / 32768.0);
    }
    return out;
  }
} // End RecordingService

class _WorkerConfig {
  final String owner;
  final int sampleRate;
  final int bufferSize;
  final String? pcmPath;
  _WorkerConfig({required this.owner, required this.sampleRate, required this.bufferSize, this.pcmPath});
}

class _RecordingWorker {
  static void entryPoint(SendPort mainSendPort) async {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    PitchDetector? detector;
    IOSink? pcmSink;
    String owner = 'unknown';
    int sampleRate = 48000;
    int bufferSize = 1024;
    double timeCursor = 0;
    final pitchBuffer = <double>[];

    await for (final message in receivePort) {
      final startTime = DateTime.now();
      
      if (message is _WorkerConfig) {
        owner = message.owner;
        sampleRate = message.sampleRate;
        bufferSize = message.bufferSize;
        detector = PitchDetector(audioSampleRate: sampleRate.toDouble(), bufferSize: bufferSize);
        timeCursor = 0;
        pitchBuffer.clear();
        
        await pcmSink?.close();
        if (message.pcmPath != null) {
          final file = File(message.pcmPath!);
          await file.parent.create(recursive: true);
          pcmSink = file.openWrite();
        } else {
          pcmSink = null;
        }
        debugPrint('[RecordingWorker] ($owner) Configured: rate=$sampleRate, buffer=$bufferSize, path=${message.pcmPath}');
      } else if (message is Uint8List) {
        if (pitchBuffer.isEmpty) debugPrint('[RecordingWorker] ($owner) First PCM chunk received: ${message.length} bytes');
        // 1. Write to PCM file if enabled
        if (pcmSink != null) {
          pcmSink.add(message);
        }

        // 2. Decode and Pitch Detect
        final samples = RecordingService._pcm16BytesToDoublesStatic(message);
        pitchBuffer.addAll(samples);
        
        // Keep pitch buffer bounded (last 2-4 windows)
        if (pitchBuffer.length > bufferSize * 4) {
          pitchBuffer.removeRange(0, pitchBuffer.length - bufferSize * 2);
        }

        final dt = samples.isEmpty ? 0.0 : samples.length / sampleRate;
        timeCursor += dt;

        if (pitchBuffer.length >= bufferSize && detector != null) {
          final window = pitchBuffer.sublist(pitchBuffer.length - bufferSize);
          try {
            final res = await detector.getPitchFromFloatBuffer(window);
            if (res.pitched && res.pitch.isFinite && res.pitch > 0) {
              final hz = res.pitch;
              final midi = 69 + 12 * (math.log(hz / 440.0) / math.ln2);
              mainSendPort.send(PitchFrame(time: timeCursor, hz: hz, midi: midi));
            } else {
              // Always send a non-pitched frame to keep the stream moving
              mainSendPort.send(PitchFrame(time: timeCursor, hz: null, midi: null));
            }
          } catch (e) {
            // Send empty frame on error
            mainSendPort.send(PitchFrame(time: timeCursor, hz: null, midi: null));
          }
        }
        
        final endTime = DateTime.now();
        final elapsed = endTime.difference(startTime).inMilliseconds;
        if (elapsed > 40) {
          debugPrint('[RecordingWorker] ($owner) SLOW PROCESSING: ${elapsed}ms for ${message.length} bytes');
        }
      } else if (message == 'stop') {
        debugPrint('[RecordingWorker] ($owner) Processing stop request...');
        await pcmSink?.flush();
        await pcmSink?.close();
        pcmSink = null;
        mainSendPort.send('done');
      }
    }
  }
}

