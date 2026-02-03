import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:audio_session/audio_session.dart';
import 'package:audioplayers/audioplayers.dart' hide AVAudioSessionCategory;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';
import 'package:record/record.dart';

enum AlignmentStrategy {
  prependSilenceToRecordingWav,
  fallbackDelayReferencePlayback,
  noAlignmentPossible
}

class SyncRunResult {
  final int refStartNs;
  final int recStartNs;
  final double offsetSec;
  final double silencePrependedSec;
  final String rawRecordingPath;
  final String alignedRecordingPath;
  final AlignmentStrategy strategy;
  final List<String> logs;

  SyncRunResult({
    required this.refStartNs,
    required this.recStartNs,
    required this.offsetSec,
    required this.silencePrependedSec,
    required this.rawRecordingPath,
    required this.alignedRecordingPath,
    required this.strategy,
    required this.logs,
  });

  @override
  String toString() {
    return 'RefStart: $refStartNs ns\n'
        'RecStart: $recStartNs ns\n'
        'Offset: ${offsetSec.toStringAsFixed(6)} s\n'
        'Strategy: $strategy\n'
        'Silence Added: ${silencePrependedSec.toStringAsFixed(6)} s';
  }
}

class TimestampSyncService {
  // Monotonic clock
  late final Stopwatch _mono;

  // Audio objects
  final AudioPlayer _refPlayer = AudioPlayer();
  final AudioPlayer _alignedPlayer = AudioPlayer(); // For playing back result
  final AudioRecorder _recorder = AudioRecorder();

  // State
  bool _isArmed = false;
  String? _tempRecordingPath;

  // Timestamp capture
  int _refStartNs = 0;
  int _recStartNs = 0;
  Completer<void>? _refStartedCompleter;
  StreamSubscription? _playerStateSub;

  // Logs
  final List<String> _logs = [];

  TimestampSyncService() {
    _mono = Stopwatch()..start();
  }

  int _monoNs() => _mono.elapsedMicroseconds * 1000;

  void _log(String message) {
    debugPrint('[SyncService] $message');
    _logs.add(message);
  }

  Future<void> init() async {
    _log('Initializing session...');
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        flags: AndroidAudioFlags.audibilityEnforced,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));
    _log('Session initialized.');
  }

  Future<void> arm({required String refAssetPath}) async {
    _log('Arming...');
    // Reset state
    _refStartNs = 0;
    _recStartNs = 0;
    _logs.clear();
    
    // Prepare players
    await _refPlayer.setSource(AssetSource(refAssetPath.replaceFirst('assets/', '')));
    await _refPlayer.setReleaseMode(ReleaseMode.stop);
    
    // Check recorder permission
    if (!await _recorder.hasPermission()) {
      _log('ERROR: No microphone permission.');
      throw Exception('No microphone permission');
    }

    _lastRefPath = refAssetPath;
    _isArmed = true;
    _log('Armed and ready.');
  }

  Stream<double?> get pitchStream => _pitchStreamController.stream;
  final StreamController<double?> _pitchStreamController = StreamController<double?>.broadcast();
  
  // Data for streaming/manual write
  IOSink? _pcmSink;
  StreamSubscription? _audioStreamSub;
  final List<double> _pitchBuffer = [];
  PitchDetector? _pitchDetector;
  int _sampleRate = 44100;

  Future<SyncRunResult> startRun({required String refAssetPath}) async {
    if (!_isArmed) await arm(refAssetPath: refAssetPath);
    _log('Starting run (Streaming Mode)...');

    final dir = await getTemporaryDirectory();
    _tempRecordingPath = '${dir.path}/sync_test_raw.pcm'; // Note: .pcm now
    
    // Setup Player trigger
    _refStartedCompleter = Completer<void>();
    _playerStateSub = _refPlayer.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.playing && _refStartNs == 0) {
        _refStartNs = _monoNs();
        _log('Ref playing detected at $_refStartNs ns');
        if (!_refStartedCompleter!.isCompleted) _refStartedCompleter!.complete();
      }
    });

    // START PLAYBACK
    final playFuture = _refPlayer.resume();

    // START RECORDING (STREAM)
    // Using PCM16 16-bit 1-channel.
    // NOTE: 'record' package on iOS/Android often defaults to 44100 or 48000.
    // We try to request 44100.
    _sampleRate = 44100;
    final config = RecordConfig(
      encoder: AudioEncoder.pcm16bits, 
      sampleRate: 44100,
      numChannels: 1,
    );
    
    // Prepare Sink
    final file = File(_tempRecordingPath!);
    if (file.existsSync()) await file.delete();
    _pcmSink = file.openWrite();
    
    // Prepare Pitch Detector
    _pitchDetector = PitchDetector(audioSampleRate: _sampleRate.toDouble(), bufferSize: 2048);
    _pitchBuffer.clear();

    final stream = await _recorder.startStream(config);
    _recStartNs = _monoNs();
    _log('Recorder stream started at $_recStartNs ns');

    // Listen to stream
    _audioStreamSub = stream.listen((data) {
      if (_pcmSink != null) {
        _pcmSink!.add(data);
      }
      _processPitch(data);
    });

    // Wait for player to actually report playing
    try {
      await playFuture;
      await _refStartedCompleter!.future.timeout(const Duration(milliseconds: 500));
    } on TimeoutException {
      _log('WARNING: Player state change timed out. Using current time as fallback.');
      if (_refStartNs == 0) _refStartNs = _monoNs();
    }

    return SyncRunResult(
      refStartNs: _refStartNs,
      recStartNs: _recStartNs,
      offsetSec: 0, 
      silencePrependedSec: 0,
      rawRecordingPath: _tempRecordingPath!,
      alignedRecordingPath: '',
      strategy: AlignmentStrategy.noAlignmentPossible,
      logs: List.from(_logs),
    );
  }
  
  void _processPitch(Uint8List bytes) {
    // bytes are Int16 Little Endian
    // Convert to double [-1.0, 1.0]
    final bd = ByteData.sublistView(bytes);
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final sample = bd.getInt16(i, Endian.little);
      _pitchBuffer.add(sample / 32768.0);
    }
    
    // Check if enough data for pitch detection
    // PitchDetector default buffer might be 2048?
    // We process whenever we have enough new data?
    // Actually PitchDetector takes a buffer and returns result.
    // We'll throttle or process chunks.
    
    // Simple sliding window or chunk processing
    const int processSize = 2048; // Must match detector buffer size ideally
    if (_pitchDetector != null && _pitchBuffer.length >= processSize) {
      final bufferToProcess = List<double>.from(_pitchBuffer.take(processSize));
      _pitchBuffer.removeRange(0, processSize ~/ 2); // Overlap? Or simply drain? Let's drain half for overlap.
      
      // Run async to not block stream listener too much (microtask)
      Future.microtask(() async {
        try {
          final result = await _pitchDetector!.getPitchFromFloatBuffer(bufferToProcess);
          if (result.pitched) {
            _pitchStreamController.add(result.pitch);
          } else {
            _pitchStreamController.add(null);
          }
        } catch (e) {
          // ignore
        }
      });
    }
  }

  Future<SyncRunResult> stopRunAndAlign() async {
    _log('Stopping...');
    await _refPlayer.stop();
    await _playerStateSub?.cancel();
    
    await _audioStreamSub?.cancel();
    await _recorder.stop(); // Stop the recorder logic
    
    // Close Sink
    await _pcmSink?.flush();
    await _pcmSink?.close();
    _pcmSink = null;
    
    _log('Stopped. PCM recorded to: $_tempRecordingPath');

    // Convert PCM to WAV so alignment logic works
    final wavPath = _tempRecordingPath!.replaceAll('.pcm', '.wav');
    await _writePcmToWav(_tempRecordingPath!, wavPath, _sampleRate);
    final micUrl = wavPath;
    
    // Update temp path to valid WAV
    _tempRecordingPath = wavPath;

    if (micUrl.isEmpty) {
      throw Exception('Recording failed, null path returned');
    }

    // Calculate Offset
    final diffNs = _recStartNs - _refStartNs;
    final offsetSec = diffNs / 1e9;
    _log('Offset calculated: $offsetSec sec (${diffNs ~/ 1000} ms)');

    double silenceToPrepend = offsetSec > 0 ? offsetSec : 0;
    
    AlignmentStrategy strategy = AlignmentStrategy.noAlignmentPossible;
    String alignedPath = micUrl;

    // Check if we can do WAV manipulation
    if (micUrl.toLowerCase().endsWith('.wav')) {
      try {
        if (silenceToPrepend > 0) {
          _log('Attempting to prepend ${silenceToPrepend.toStringAsFixed(4)}s of silence to WAV...');
          alignedPath = await _prependSilenceToWav(micUrl, silenceToPrepend);
          strategy = AlignmentStrategy.prependSilenceToRecordingWav;
          _log('Success. Aligned file: $alignedPath');
        } else {
           strategy = AlignmentStrategy.fallbackDelayReferencePlayback;
           _log('Negative offset. Will use playback delay strategy.');
        }
      } catch (e) {
        _log('WAV manipulation failed: $e');
        strategy = AlignmentStrategy.noAlignmentPossible;
      }
    } else {
       _log('Not a WAV file ($micUrl). Cannot prepend silence manually.');
       strategy = AlignmentStrategy.fallbackDelayReferencePlayback;
    }

    return SyncRunResult(
      refStartNs: _refStartNs,
      recStartNs: _recStartNs,
      offsetSec: offsetSec,
      silencePrependedSec: silenceToPrepend,
      rawRecordingPath: micUrl,
      alignedRecordingPath: alignedPath,
      strategy: strategy,
      logs: List.from(_logs),
    );
  }
  
  Future<void> _writePcmToWav(String pcmPath, String wavPath, int sampleRate) async {
    final pcmFile = File(pcmPath);
    if (!await pcmFile.exists()) return;
    
    final pcmBytes = await pcmFile.readAsBytes();
    final wavFile = File(wavPath);
    final sink = wavFile.openWrite();
    
    const int numChannels = 1;
    const int bitsPerSample = 16;
    final int byteRate = sampleRate * numChannels * 2;
    const int blockAlign = numChannels * 2;
    
    // RIFF header
    sink.add(utf8.encode('RIFF'));
    final fileSize = 36 + pcmBytes.length;
    _writeInt32(sink, fileSize);
    sink.add(utf8.encode('WAVE'));
    
    // fmt chunk
    sink.add(utf8.encode('fmt '));
    _writeInt32(sink, 16); // Subchunk1Size
    _writeInt16(sink, 1); // AudioFormat 1 = PCM
    _writeInt16(sink, numChannels);
    _writeInt32(sink, sampleRate);
    _writeInt32(sink, byteRate);
    _writeInt16(sink, blockAlign);
    _writeInt16(sink, bitsPerSample);
    
    // data chunk
    sink.add(utf8.encode('data'));
    _writeInt32(sink, pcmBytes.length);
    sink.add(pcmBytes);
    
    await sink.flush();
    await sink.close();
  }
  
  void _writeInt32(IOSink sink, int value) {
    final b = Uint8List(4);
    b.buffer.asByteData().setInt32(0, value, Endian.little);
    sink.add(b);
  }
  
  void _writeInt16(IOSink sink, int value) {
    final b = Uint8List(2);
    b.buffer.asByteData().setInt16(0, value, Endian.little);
    sink.add(b);
  }
  
  // Minimal manual WAV parser/writer
  Future<String> _prependSilenceToWav(String originalPath, double valSeconds) async {
    final file = File(originalPath);
    final bytes = await file.readAsBytes();
    final raf = await file.open(mode: FileMode.read);
    
    // Read header info (Little Endian)
    // RIFF (4) + Size (4) + WAVE (4)
    // fmt (4) + Size (4) + AudioFormat(2) + NumChannels(2) + SampleRate(4) + ByteRate(4) + BlockAlign(2) + BitsPerSample(2)
    // data (4) + Size (4)
    
    // We just assume standard header layout for simplicity or use simplistic parsing.
    // Ideally find "fmt " and "data ".
    
    // final headerReq = ByteData.sublistView(bytes, 0, 44); // Assume 44 byte header first
    
    // Basic validations
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    if (riff != 'RIFF') throw Exception('Not a RIFF file');
    
    // Locate fmt chunk
    int fmtOffset = 12;
    while(String.fromCharCodes(bytes.sublist(fmtOffset, fmtOffset+4)) != 'fmt ') {
       fmtOffset += 1;
       if (fmtOffset > 100) throw Exception('fmt chunk not found early');
    }
    
    final fmtSize = bytes.buffer.asByteData().getUint32(fmtOffset+4, Endian.little);
    final audioFormat = bytes.buffer.asByteData().getUint16(fmtOffset+8, Endian.little);
    final numChannels = bytes.buffer.asByteData().getUint16(fmtOffset+10, Endian.little);
    final sampleRate = bytes.buffer.asByteData().getUint32(fmtOffset+12, Endian.little);
    final bitsPerSample = bytes.buffer.asByteData().getUint16(fmtOffset+22, Endian.little);
    
    if (audioFormat != 1) throw Exception('Not PCM (format=$audioFormat)');
    
    // Locate data chunk
    int dataOffset = fmtOffset + 8 + fmtSize;
    // Walk through chunks until data
    while(dataOffset < bytes.length - 8 && String.fromCharCodes(bytes.sublist(dataOffset, dataOffset+4)) != 'data') {
       final size = bytes.buffer.asByteData().getUint32(dataOffset+4, Endian.little);
       dataOffset += 8 + size;
    }
    
    if (String.fromCharCodes(bytes.sublist(dataOffset, dataOffset+4)) != 'data') {
        throw Exception('No data chunk found');
    }
    
    final oldDataSize = bytes.buffer.asByteData().getUint32(dataOffset+4, Endian.little);
    final int bytesPerSample = bitsPerSample ~/ 8;
    final int frameSize = numChannels * bytesPerSample;
    
    final int framesToAdd = (valSeconds * sampleRate).round();
    final int bytesToAdd = framesToAdd * frameSize;
    
    final newPath = originalPath.replaceAll('.wav', '_aligned.wav');
    final newFile = File(newPath);
    final sink = await newFile.open(mode: FileMode.write);
    
    // HEADER logic:
    // We basically copy the header until the data size, update file size and data size.
    
    // 1. Write RIFF header [0-12]
    // Update File Size = oldFileSize + bytesToAdd
    await sink.writeFrom(bytes.sublist(0, 4)); // RIFF
    
    final int oldFileSize = bytes.length - 8;
    final int newFileSize = oldFileSize + bytesToAdd;
    final sizeBytes = Uint8List(4)..buffer.asByteData().setUint32(0, newFileSize, Endian.little);
    await sink.writeFrom(sizeBytes);
    
    await sink.writeFrom(bytes.sublist(8, dataOffset + 4)); // WAVE...fmt...data tag
    
    // 2. Write Data Size
    final int newDataSize = oldDataSize + bytesToAdd;
    final dataSizeBytes = Uint8List(4)..buffer.asByteData().setUint32(0, newDataSize, Endian.little);
    await sink.writeFrom(dataSizeBytes);
    
    // 3. Write Silence
    final silenceChunk = Uint8List(bytesToAdd); // Zero initialized
    await sink.writeFrom(silenceChunk);
    
    // 4. Write Old Data
    await sink.writeFrom(bytes.sublist(dataOffset + 8));
    
    await sink.close();
    await raf.close();
    
    return newPath;
  }

  Future<void> playAligned() async {
    // This method assumes the last run state is available or could arguably take a result.
    // But per instructions, it's stateful on the service or controlled by the UI via service.
    // For simplicity, we assume the UI calls playAligned() after a stop.
    // But wait, the prompt says "Plays the reference + aligned recording together".
    // We need 2 players.
    
    // We need the result from the last run to know what to do.
    // Let's store the last result? Or re-calculate? 
    // The problem is `stopRunAndAlign` returns the result but doesn't persist it in the service fully.
    // We'll rely on our internal state variables or cached paths.
    
    if (_tempRecordingPath == null) return;
    
    // Re-read offset to decide strategy again or use stored strategy
    final diffNs = _recStartNs - _refStartNs;
    final offsetSec = diffNs / 1e9;
    
    final recPath = _tempRecordingPath!.replaceAll('.wav', '_aligned.wav');
    final hasAlignedFile = File(recPath).existsSync();
    
    // Ref Player Setup
    // Note: ref player is _refPlayer
    // Aligned/Rec player is _alignedPlayer
    
    // Reset players
    await _refPlayer.stop();
    await _alignedPlayer.stop();
    
    // String refSource = 'assets/audio/ref.wav'; // Hardcoded fallback or use what was passed to arm
    // Ideally we should store the asset path used in arm.
    // Let's assume a default or add a field. 
    // I'll grab it from the arm() call if I stored it, but I didn't store it.
    // I'll make arm() store it.
    
    // Actually, let's just use what's currently set in _refPlayer if possible, or reload.
    // _refPlayer.source might be null if stopped? 
    // Safest to just reload. I will add a field `_lastRefPath`.
    if (_lastRefPath == null) return;
    
    await _refPlayer.setSource(AssetSource(_lastRefPath!.replaceFirst('assets/', '')));
    
    if (hasAlignedFile) {
        // We have a physical file with silence prepended (Strategy A)
        await _alignedPlayer.setSource(DeviceFileSource(recPath));
        
        // Just play both immediately
        _log('Playing both immediately (Aligned File)...');
        await Future.wait([
          _refPlayer.resume(),
          _alignedPlayer.resume(),
        ]);
    } else {
        // Strategy B: Fallback Delay
        final rawPath = _tempRecordingPath!;
        await _alignedPlayer.setSource(DeviceFileSource(rawPath));
        
        if (offsetSec >= 0) {
            // Rec started LATER. 
            // We need to delay Rec by offsetSec so it matches Ref? 
            // WAIT. 
            // Rec started at 120. Ref at 100.
            // Rec content is "audio from 120 onwards".
            // Ref content is "audio from 100 onwards".
            // To align:
            // Ref at 0s -> plays t=100.
            // Rec at 0s -> plays t=120. 
            // This is MISALIGNED by 20ms.
            // We want Rec to play same acoustic event.
            // Clap at 150.
            // Ref has clap at 50ms.
            // Rec has clap at 30ms.
            // If we play Ref at 0, clap is at 50ms.
            // We want Rec clap to be at 50ms.
            // But Rec clap is at 30ms.
            // We need to DELAY Rec start by 20ms.
            // So: delay Rec by offsetSec.
            _log('Playing Ref immediately, Rec delayed by ${offsetSec}s');
            _refPlayer.resume(); // No await
            Future.delayed(Duration(milliseconds: (offsetSec * 1000).round()), () {
               _alignedPlayer.resume();
            });
        } else {
            // offset < 0. Rec started BEFORE Ref.
            // Rec at 80. Ref at 100.
            // Clap at 150.
            // Rec clap at 70ms. Ref clap at 50ms.
            // Play Ref at 0 -> clap at 50ms.
            // Play Rec at 0 -> clap at 70ms.
            // Rec is LATE.
            // We need to play Rec EARLIER (skip 20ms) OR Delay Ref by 20ms.
            // Delaying Ref is easier.
            // Delay Ref by -offset.
             _log('Playing Rec immediately, Ref delayed by ${-offsetSec}s');
            _alignedPlayer.resume();
            Future.delayed(Duration(milliseconds: (-offsetSec * 1000).round()), () {
               _refPlayer.resume();
            });
        }
    }
  }

  String? _lastRefPath; // To remembering what to play
  
  // Make sure to update arm to store this
  Future<void> dispose() async {
    await _refPlayer.dispose();
    await _alignedPlayer.dispose();
    await _recorder.dispose();
  }
}
