import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

// NEW
import 'package:flutter_sound/flutter_sound.dart';
import 'pitch_isolate_processor.dart';

enum AlignmentStrategy {
  signalAnalysis,
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
  final PitchIsolateProcessor _pitchProcessor = PitchIsolateProcessor();
  bool _livePitchEnabled = true;
  
  // Debug stats
  int _audioChunksSeen = 0;
  Timer? _debugTimer;
  
  // Manual WAV writing state (Removed RAF, now memory buffer)
  // Max memory buffer 30MB (~5 mins of 48k mono 16bit)
  static const int _maxCaptureBytes = 30 * 1024 * 1024;
  final List<Uint8List> _audioChunks = [];
  int _capturedBytes = 0;
  int _droppedBytes = 0;

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
  final int _sampleRate = 48000; // strongly recommended on Android
  final int _numChannels = 1;

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

    // Init isolate
    await _pitchProcessor.init();
    _pitchProcessor.resultStream.listen((hz) {
      _pitchStreamController.add(hz);
    });
    
    // Start debug timer
    _debugTimer?.cancel();
    _debugTimer = Timer.periodic(const Duration(seconds: 2), (t) {
      if (_isArmed || _recStartNs > 0) { // rough check if active
         _logStats();
      }
    });

    _isInited = true;
    _log('flutter_sound sessions opened & isolate inited.');
  }
  
  void setLivePitchEnabled(bool enabled) {
    _livePitchEnabled = enabled;
  }

  // Marker config
  // Marker config
  static const int _clickSamples = 480; // 10ms at 48k
  static const int _silenceSamples = 2400; // 50ms padding
  int _refMarkerIndex = 0; // Where the click starts in the reference file

  // We track where we *expect* the marker to be in the reference file (usually 0)
  // But since we generate it, we know it starts at 0.
  
  void _logStats() {
    _log('Stats: AudioChunks=$_audioChunksSeen, '
         'PitchSent=${_pitchProcessor.chunksSent}, '
         'PitchProc=${_pitchProcessor.chunksProcessed}, '
         'Dropped=${_pitchProcessor.chunksDropped}, '
         'AvgTime=${_pitchProcessor.avgComputeMs.toStringAsFixed(2)}ms');
  }

  Future<void> arm({required String refAssetPath}) async {
    _lastRefAssetPath = refAssetPath;
    // Cancel old subs
    await _refProgSub?.cancel();
    _refProgSub = null;
    await _recStreamSub?.cancel();
    _recStreamSub = null;
    
    // Clear buffers
    _audioChunks.clear();
    _capturedBytes = 0;
    _droppedBytes = 0;
    
    // Reset stats
    _audioChunksSeen = 0;
    _pitchProcessor.chunksDropped = 0;
    _pitchProcessor.chunksSent = 0;
    _pitchProcessor.chunksProcessed = 0;

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
    // We collect in memory and write AFTER stop.
    
    // Set file path for writing later
    final tempDir = await getTemporaryDirectory();
    _rawWavPath = '${tempDir.path}/sync_raw.wav';
    
    // Clear buffers (just in case)
    _audioChunks.clear();
    _capturedBytes = 0;
    _droppedBytes = 0;
    
    await _recStreamSub?.cancel();
    _recStreamSub = _audioStreamController.stream.listen((data) {
        if (_recStartNs == 0 && data.isNotEmpty) {
          _recStartNs = _monoNs();
          _log('Rec FIRST pcm chunk at $_recStartNs ns (bytes=${data.length})');
        }
        
        // Buffer Logic (Ring Buffer)
        _audioChunks.add(data);
        _capturedBytes += data.length;
        
        // Enforce cap
        while (_capturedBytes > _maxCaptureBytes && _audioChunks.isNotEmpty) {
           final removed = _audioChunks.removeAt(0);
           _capturedBytes -= removed.length;
           _droppedBytes += removed.length;
        }
        
         // Process pitch (non-blocking isolate mailbox)
        if (_livePitchEnabled) {
          _audioChunksSeen++;
          _pitchProcessor.process(data);
        }
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
    // 3) Start reference playback (from asset)
    // flutter_sound expects a URI or a path. For assets, the common pattern is:
    // - load asset to a temp file, then play from that file path.
    // INJECT AUDIBLE CLICK (Signal Analysis)
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

  // _processPitch removed

  Future<SyncRunResult> stopRunAndAlign() async {
    _log('Stopping...');

    await _recorder.stopRecorder();
    await _playerRef.stopPlayer();
    
    await _recStreamSub?.cancel();
    
    // Finalize WAV file (update header)
    // Write accumulated buffer to WAV
    try {
      if (_capturedBytes > 0 && _rawWavPath != null) {
        final f = File(_rawWavPath!);
        final raf = await f.open(mode: FileMode.write);

        // Header
        final header = _buildWavHeader(_capturedBytes, _sampleRate, _numChannels);
        await raf.writeFrom(header);
        
        // Data chunks
        for (final chunk in _audioChunks) {
          await raf.writeFrom(chunk);
        }
        await raf.close();
        
        _log('WAV written. Bytes=$_capturedBytes, Dropped=$_droppedBytes. Path=$_rawWavPath');
        
        // Free memory
        _audioChunks.clear();
      } else {
        _log('No captured bytes to write.');
      }
    } catch (e) {
      _log('Error writing WAV: $e');
    }

    _log('Stopped. rawWav=$_rawWavPath');
    
    // --- SIGNAL ANALYSIS & ALIGNMENT ---
    _log('Starting signal analysis...');

    int recMarkerIndex = -1;
    File? recRawFile;
    if (_rawWavPath != null) {
      recRawFile = File(_rawWavPath!);
      if (recRawFile.existsSync()) {
        final bytes = await recRawFile.readAsBytes();
        // Skip 44 byte header
        if (bytes.length > 44) {
          recMarkerIndex = _findMarkerSampleIndex(bytes.sublist(44));
        }
      }
    }

    _log('Marker detection: RefIndex=$_refMarkerIndex, RecIndex=$recMarkerIndex');

    _alignedWavPath = null;
    AlignmentStrategy strategy = AlignmentStrategy.noAlignmentPossible;
    double offsetSec = 0.0;

    if (recMarkerIndex != -1 && recRawFile != null) {
       // Offset: How many samples later did the recorder hear it?
       // RecIndex is usually > RefIndex because of latency + travel time.
       // Diff = Rec - Ref
       final diffSamples = recMarkerIndex - _refMarkerIndex;
       offsetSec = diffSamples / _sampleRate;
       
       _log('Offset calculated (signal): $diffSamples samples ($offsetSec sec)');
       
       final dir = await getTemporaryDirectory();
       _alignedWavPath = '${dir.path}/sync_aligned.wav';
       
       try {
         if (offsetSec > 0) {
           // Recorder is LATE (lag). We must TRIM the start to align.
           await _trimStartOfWav(
              inputPath: _rawWavPath!,
              outputPath: _alignedWavPath!,
              trimSeconds: offsetSec, 
           );
           strategy = AlignmentStrategy.signalAnalysis;
           _log('Aligned by trimming ${offsetSec}s.');
         } else {
           // Recorder is EARLY. Pad.
           final padSec = -offsetSec;
           await _prependSilenceToWav(
             _rawWavPath!,
             padSec,
             outputPath: _alignedWavPath!,
           );
           strategy = AlignmentStrategy.signalAnalysis;
           _log('Aligned by padding ${padSec}s.');
         }
       } catch (e) {
          _log('Alignment failed: $e');
          _alignedWavPath = null;
       }
    } else {
      _log('Marker NOT FOUND in recording. Cannot align.');
    }
    
    return SyncRunResult(
      recStartNs: _recStartNs,
      refStartNs: _refStartNs,
      offsetSec: offsetSec,
      silencePrependedSec: 0.0, 
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

  /// Standard asset materialization with CLICK INJECTION
  Future<String> _materializeAssetToFile(String assetPath) async {
    // 1. Load asset bytes
    final assetByteData = await rootBundle.load(assetPath);
    final assetBytes = assetByteData.buffer.asUint8List();
    
    // 2. Prepare Marker
    // [Click (10ms)] [Silence (50ms)] [Asset...]
    _refMarkerIndex = 0; 
    
    final clickBytes = Uint8List(_clickSamples * 2);
    final bd = ByteData.sublistView(clickBytes);
    // Square wave click
    for (int i = 0; i < _clickSamples; i++) {
       // Full scale is 32767. Let's use 30000.
       bd.setInt16(i * 2, 30000, Endian.little);
    }
    
    final silenceBytes = Uint8List(_silenceSamples * 2); 
    
    // 3. Assemble
    int assetHeaderLen = 44;
    if (assetBytes.length < 44) assetHeaderLen = 0; 
    
    final assetPcm = assetBytes.sublist(assetHeaderLen);
    
    final totalLen = clickBytes.length + silenceBytes.length + assetPcm.length;
    final header = _buildWavHeader(totalLen, _sampleRate, _numChannels);
    
    final bb = BytesBuilder();
    bb.add(header);
    bb.add(clickBytes);
    bb.add(silenceBytes);
    bb.add(assetPcm);
    
    // Write to temp
    final dir = await getTemporaryDirectory();
    const fileName = 'ref_with_marker.wav';
    final tempFile = File('${dir.path}/$fileName');
    await tempFile.writeAsBytes(bb.toBytes());
    
    return tempFile.path;
  }
  
  // Scans for first sample > threshold
  int _findMarkerSampleIndex(Uint8List pcmBytes) {
     final bd = ByteData.sublistView(pcmBytes);
     final numSamples = pcmBytes.length ~/ 2;
     // Threshold: 0.7 of 32768 ~= 22937. Let's say 20000.
     const threshold = 20000;
     
     for (int i=0; i < numSamples; i++) {
        final val = bd.getInt16(i * 2, Endian.little);
        if (val.abs() > threshold) {
           return i;
        }
     }
     return -1;
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
    _pitchProcessor.dispose();
    _debugTimer?.cancel();
    
    // RAF cleanup removed (memory only now)

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
