import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

// NEW
import 'package:flutter_sound/flutter_sound.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';

enum AlignmentStrategy {
  prependSilenceToRecordingWav,
  fallbackDelayReferencePlayback,
  noAlignmentPossible,
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
  final Stopwatch _mono = Stopwatch()..start();
  int _monoNs() => _mono.elapsedMicroseconds * 1000;

  // flutter_sound objects
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _playerRef = FlutterSoundPlayer();
  final FlutterSoundPlayer _playerRec = FlutterSoundPlayer();

  // State
  bool _isInited = false;
  bool _isArmed = false;

  String? _lastRefAssetPath;
  String? _rawWavPath;
  String? _alignedWavPath;

  // Timestamp capture
  int _refStartNs = 0;
  int _recStartNs = 0;

  // Subscriptions
  StreamSubscription? _recStreamSub;
  StreamSubscription<PlaybackDisposition>? _refProgSub;

  // Recorder stream controller for PCM16
  // flutter_sound startRecorder(toStream:) expects a StreamSink<Uint8List>
  final StreamController<Uint8List> _audioStreamController = StreamController<Uint8List>.broadcast();

  // Pitch stream
  Stream<double?> get pitchStream => _pitchStreamController.stream;
  final StreamController<double?> _pitchStreamController =
      StreamController<double?>.broadcast();
  
  // Pitch processing state
  final List<double> _pitchBuffer = [];
  PitchDetector? _pitchDetector;
  
  // Manual WAV writing state
  RandomAccessFile? _wavRAF;
  int _wavDataLength = 0;
  File? _wavFile;

  // Logs
  final List<String> _logs = [];
  void _log(String m) {
    debugPrint('[SyncService/fs] $m');
    _logs.add(m);
  }

  // Mute state
  bool _muteRef = false;
  bool _muteRec = false;

  // Config
  int _sampleRate = 48000; // strongly recommended on Android
  int _numChannels = 1;

  Future<void> init() async {
    if (_isInited) return;

    _log('Opening flutter_sound sessions...');
    await _recorder.openRecorder();
    await _playerRef.openPlayer();
    await _playerRec.openPlayer();

    // Optional: reduce progress callback interval
    // Smaller interval => more precise "first tick"
    _playerRef.setSubscriptionDuration(const Duration(milliseconds: 20));
    _playerRec.setSubscriptionDuration(const Duration(milliseconds: 20));
    _recorder.setSubscriptionDuration(const Duration(milliseconds: 20));

    _isInited = true;
    _log('flutter_sound sessions opened.');
  }

  Future<void> arm({required String refAssetPath}) async {
    _lastRefAssetPath = refAssetPath;
    // Cancel old subs
    await _refProgSub?.cancel();
    _refProgSub = null;
    await _recStreamSub?.cancel();
    _recStreamSub = null;
    
    // Close any open wav raf
    if (_wavRAF != null) {
      await _wavRAF!.close();
      _wavRAF = null;
    }
    
    // Pitch detector init
    _pitchDetector = PitchDetector(audioSampleRate: _sampleRate.toDouble(), bufferSize: 2048);
    _pitchBuffer.clear();

    // Apply mute volumes immediately
    await _applyMuteVolumes();

    _isArmed = true;
    _log('Armed. ref=$refAssetPath sr=$_sampleRate ch=$_numChannels');
  }

  Future<void> setMuteRef(bool muted) async {
    _muteRef = muted;
    await _applyMuteVolumes();
  }

  Future<void> setMuteRec(bool muted) async {
    _muteRec = muted;
    await _applyMuteVolumes();
  }

  Future<void> _applyMuteVolumes() async {
    // flutter_sound uses setVolume(0..1)
    try {
      await _playerRef.setVolume(_muteRef ? 0.0 : 1.0);
    } catch (_) {}
    try {
      await _playerRec.setVolume(_muteRec ? 0.0 : 1.0);
    } catch (_) {}
  }

  Future<SyncRunResult> startRun({required String refAssetPath}) async {
    _lastRefAssetPath = refAssetPath;
    if (!_isArmed) await arm(refAssetPath: refAssetPath);

    _log('Starting run...');

    final dir = await getTemporaryDirectory();
    _rawWavPath = '${dir.path}/sync_raw.wav';
    final rawFile = File(_rawWavPath!);
    if (rawFile.existsSync()) {
      await rawFile.delete();
    }

    _refStartNs = 0;
    _recStartNs = 0;

    // 1) Set refStartNs on first NON-ZERO progress tick
    await _refProgSub?.cancel();
    _refProgSub = _playerRef.onProgress?.listen((d) {
      // d.position is a Duration
      if (_refStartNs == 0 && d.position.inMilliseconds > 0) {
        _refStartNs = _monoNs();
        _log('Ref first NON-ZERO position tick at $_refStartNs ns (pos=${d.position})');
      }
    });

    // 2) Start recorder -> toStream (PCM16)
    // We will manually write the WAV file to ensure we get the stream data for pitch tracking AND file saving.
    
    // Prepare WAV file
    final tempDir = await getTemporaryDirectory();
    _rawWavPath = '${tempDir.path}/sync_raw.wav';
    _wavFile = File(_rawWavPath!);
    // Open as RandomAccessFile with write mode (truncates)
    _wavRAF = await _wavFile!.open(mode: FileMode.write);
    _wavDataLength = 0;
    
    // Write placeholder header (44 bytes)
    await _wavRAF!.writeFrom(Uint8List(44));
    
    await _recStreamSub?.cancel();
    _recStreamSub = _audioStreamController.stream.listen((data) {
        if (_recStartNs == 0 && data.isNotEmpty) {
          _recStartNs = _monoNs();
          _log('Rec FIRST pcm chunk at $_recStartNs ns (bytes=${data.length})');
        }
        
        // Write to file (async fire and forget? No, RAF operations are async futures)
        // We should chain them? For now, we trust single threaded event loop + await
        // Actually inside listen callback we can't await properly without pausing stream.
        // It's better to use a sync write if possible or queue.
        // RAF has sync methods! use writeFromSync to avoid concurrency issues in stream listener?
        // Yes, let's use sync for safety and simplicity in listener.
        
        if (_wavRAF != null) {
          try {
             _wavRAF!.writeFromSync(data);
             _wavDataLength += data.length;
          } catch (e) {
             print('Error writing wav: $e');
          }
        }
        
        // Process pitch
        _processPitch(data);
    });

    // Start recorder: PCM16 to Stream
    // Note: ensure we use Codec.pcm16 to get raw samples, not WAV container
    await _recorder.startRecorder(
      codec: Codec.pcm16, 
      sampleRate: _sampleRate,
      numChannels: _numChannels,
      toStream: _audioStreamController.sink,
    );
    _log('Recorder started (Stream -> File + Pitch).');

    // Timestamp immediately fallback (if stream didn't fire yet)
    if (_recStartNs == 0) {
      _recStartNs = _monoNs();
      _log('Rec started at $_recStartNs ns (stream fallback)');
    }

    // 3) Start reference playback (from asset)
    // flutter_sound expects a URI or a path. For assets, the common pattern is:
    // - load asset to a temp file, then play from that file path.
    final refPath = await _materializeAssetToFile(refAssetPath);
    _log('Ref materialized to file: $refPath');

    await _playerRef.startPlayer(
      fromURI: refPath,
      codec: Codec.pcm16WAV, // your ref is wav; if not, you can omit or set appropriately
      whenFinished: () => _log('Ref finished.'),
    );

    // If we never got a non-zero position tick quickly, fallback to "now" after a short delay
    await Future.delayed(const Duration(milliseconds: 250));
    if (_refStartNs == 0) {
      _refStartNs = _monoNs();
      _log('WARNING: No NON-ZERO ref position tick yet; fallback refStartNs=$_refStartNs');
    }

    return SyncRunResult(
      refStartNs: _refStartNs,
      recStartNs: _recStartNs,
      offsetSec: 0,
      silencePrependedSec: 0,
      rawRecordingPath: _rawWavPath!,
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
    
    // Simple sliding window or chunk processing
    const int processSize = 2048; // Must match detector buffer size ideally
    if (_pitchDetector != null && _pitchBuffer.length >= processSize) {
      final bufferToProcess = List<double>.from(_pitchBuffer.take(processSize));
      _pitchBuffer.removeRange(0, processSize ~/ 2); // Overlap 50%
      
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

    await _recorder.stopRecorder();
    await _playerRef.stopPlayer();
    
    await _recStreamSub?.cancel();
    
    // Finalize WAV file (update header)
    if (_wavRAF != null) {
      try {
        // Go back to start and write real header
        _wavRAF!.setPositionSync(0);
        final header = _buildWavHeader(_wavDataLength, _sampleRate, _numChannels);
        _wavRAF!.writeFromSync(header);
        _wavRAF!.closeSync(); // Close sync to ensure it's flushed/closed before we read it
      } catch (e) {
        _log('Error finalizing WAV RAF: $e');
      }
      _wavRAF = null;
      _log('WAV finalized (RAF). len=$_wavDataLength');
    }

    _log('Stopped. rawWav=$_rawWavPath');
    
    // Logic:
    // Offset = RecStart - RefStart
    // If Offset > 0: Rec started LATER. We missed the start of the song. 
    //    Prepend silence of duration `offset`.
    // If Offset < 0: Rec started EARLIER. 
    //    Trim the start of duration `-offset`.
    
    final offsetNs = _recStartNs - _refStartNs;
    final offsetSec = offsetNs / 1e9;
    _log('Offset calculated: $offsetSec sec (${(offsetSec*1000).toStringAsFixed(3)} ms)');

    _alignedWavPath = null;
    AlignmentStrategy strategy = AlignmentStrategy.noAlignmentPossible;
    
    if (_rawWavPath != null) {
      final dir = await getTemporaryDirectory();
      _alignedWavPath = '${dir.path}/sync_aligned.wav';
      
      try {
        if (offsetSec > 0) {
          // Rec started later -> Prepend silence (PAD)
          await _prependSilenceToWav(
            _rawWavPath!,
            offsetSec,
            outputPath: _alignedWavPath!,
          );
          strategy = AlignmentStrategy.prependSilenceToRecordingWav;
          _log('Aligned by padding ${offsetSec}s silence.');
        } else {
          // Rec started earlier -> Trim start
          final trimSeconds = -offsetSec;
          await _trimStartOfWav(
             inputPath: _rawWavPath!,
             outputPath: _alignedWavPath!,
             trimSeconds: trimSeconds,
          );
          strategy = AlignmentStrategy.prependSilenceToRecordingWav; // Reusing strategy enum
           _log('Aligned by trimming ${trimSeconds}s from start.');
        }
      } catch (e) {
        _log('Alignment failed: $e');
        _alignedWavPath = null;
      }
    }
    
    return SyncRunResult(
      recStartNs: _recStartNs,
      refStartNs: _refStartNs,
      offsetSec: offsetSec,
      silencePrependedSec: offsetSec > 0 ? offsetSec : 0.0,
      rawRecordingPath: _rawWavPath!,
      alignedRecordingPath: _alignedWavPath ?? '',
      strategy: strategy, 
      logs: List.from(_logs),
    );
  }

  Future<void> playAligned() async {
    _log('playAligned called.');
    if (_lastRefAssetPath == null || _rawWavPath == null) {
      _log('Cannot play: ref or raw path null.');
      return;
    }
    
    // Check files
    final rawFile = File(_rawWavPath!);
    if (rawFile.existsSync()) {
      _log('Raw WAV exists, size=${rawFile.lengthSync()}');
    } else {
      _log('Raw WAV missing!');
    }
    
    if (_alignedWavPath != null) {
       final alignedFile = File(_alignedWavPath!);
       if (alignedFile.existsSync()) {
         _log('Aligned WAV exists, size=${alignedFile.lengthSync()}');
       } else {
         _log('Aligned WAV path set but file missing!');
       }
    }
    
    // Always use the aligned path if available.
    // If null (failed alignment), fall back to raw (which won't be synced).
    final recPath = _alignedWavPath ?? _rawWavPath!;
    final refPath = await _materializeAssetToFile(_lastRefAssetPath!);
    _log('Playing: Ref=$refPath, Rec=$recPath');

    await _applyMuteVolumes();
    _log('Mute state: Ref=$_muteRef, Rec=$_muteRec');

    // Stop any prior playback
    if (_playerRef.isPlaying) await _playerRef.stopPlayer();
    if (_playerRec.isPlaying) await _playerRec.stopPlayer();

    _log('Starting playback...');
    try {
      await _playerRef.startPlayer(fromURI: refPath, whenFinished: () { _log('Ref finished'); });
      await _playerRec.startPlayer(fromURI: recPath, whenFinished: () { _log('Rec finished'); });
    } catch (e) {
      _log('Error starting playback: $e');
    }
  }

  /// For flutter_sound: assets aren’t directly playable by URI on all platforms.
  /// Materialize asset -> temp file.
  Future<String> _materializeAssetToFile(String assetPath) async {
    // Load asset bytes using rootBundle
    final byteData = await rootBundle.load(assetPath);
    final bytes = byteData.buffer.asUint8List();
    
    // Write to temp file
    final dir = await getTemporaryDirectory();
    final fileName = assetPath.split('/').last;
    final tempFile = File('${dir.path}/$fileName');
    await tempFile.writeAsBytes(bytes);
    
    return tempFile.path;
  }

  // --- WAV prepend helpers (same logic you already had, slightly cleaned) ---

  // --- WAV Helpers ---

  Uint8List _buildWavHeader(int dataSize, int sampleRate, int channels) {
    final fileSize = dataSize + 36;
    final byteRate = sampleRate * channels * 2; // 16-bit
    final blockAlign = channels * 2;

    final header = ByteData(44);
    final view = header.buffer.asUint8List();

    // RIFF
    view.setRange(0, 4, utf8.encode('RIFF'));
    header.setUint32(4, fileSize, Endian.little);
    view.setRange(8, 12, utf8.encode('WAVE'));
    
    // fmt (PCM)
    view.setRange(12, 16, utf8.encode('fmt '));
    header.setUint32(16, 16, Endian.little); // Subchunk1Size
    header.setUint16(20, 1, Endian.little); // AudioFormat 1=PCM
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, 16, Endian.little); // Bits per sample
    
    // data
    view.setRange(36, 40, utf8.encode('data'));
    header.setUint32(40, dataSize, Endian.little);

    return view;
  }
  
  Future<void> _trimStartOfWav({required String inputPath, required String outputPath, required double trimSeconds}) async {
     final inputFile = File(inputPath);
     final bytes = await inputFile.readAsBytes();
     
     // Minimum header size
     if (bytes.length < 44) return;
     
     final sampleRate = _sampleRate; 
     final channels = _numChannels;
     final bytesPerSec = sampleRate * channels * 2;
     final trimBytes = (trimSeconds * bytesPerSec).round();
     
     final blockAlign = channels * 2;
     final alignedTrimBytes = (trimBytes ~/ blockAlign) * blockAlign;
     
     // Skip original header
     if (44 + alignedTrimBytes >= bytes.length) {
       // Trimmed everything
       final header = _buildWavHeader(0, sampleRate, channels);
       await File(outputPath).writeAsBytes(header);
       return;
     }

     final newLength = (bytes.length - 44) - alignedTrimBytes;
     final header = _buildWavHeader(newLength, sampleRate, channels);
     
     final outBytes = BytesBuilder();
     outBytes.add(header);
     outBytes.add(bytes.sublist(44 + alignedTrimBytes));
     
     await File(outputPath).writeAsBytes(outBytes.toBytes());
  }

  Future<String> _prependSilenceToWav(String inputPath, double silenceSeconds, {String? outputPath}) async {
    final inFile = File(inputPath);
    final bytes = await inFile.readAsBytes();
    
    final sampleRate = _sampleRate;
    final channels = _numChannels;
    final bytesPerSec = sampleRate * channels * 2;
    final silenceBytesCount = (silenceSeconds * bytesPerSec).round();
    final blockAlign = channels * 2;
    final alignedSilenceBytes = (silenceBytesCount ~/ blockAlign) * blockAlign;
    
    // Assume 44 byte header for files we created
    final currentDataLen = bytes.length - 44;
    final newDataLen = currentDataLen + alignedSilenceBytes;
    
    final header = _buildWavHeader(newDataLen, sampleRate, channels);
    final silence = Uint8List(alignedSilenceBytes); 
    
    final outPath = outputPath ?? inputPath; 
    
    final bb = BytesBuilder();
    bb.add(header);
    bb.add(silence);
    if (bytes.length > 44) {
      bb.add(bytes.sublist(44));
    }
    
    await File(outPath).writeAsBytes(bb.toBytes());
    return outPath;
  }

  Future<void> dispose() async {
    await _refProgSub?.cancel();
    await _recStreamSub?.cancel();
    await _audioStreamController.close();
    await _pitchStreamController.close();
    
    if (_wavRAF != null) {
      try { _wavRAF!.closeSync(); } catch (_) {}
      _wavRAF = null;
    }

    // flutter_sound doesn't have isOpen() method, just try to close
    try {
      await _playerRef.closePlayer();
    } catch (_) {}
    try {
      await _playerRec.closePlayer();
    } catch (_) {}
    try {
      await _recorder.closeRecorder();
    } catch (_) {}

    _isInited = false;
  }
}