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
import 'ultrasonic_marker.dart';

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
  static const double _markerStartHz = 19000;
  static const double _markerEndHz = 21000;
  static const int _markerDurationMs = 30;
  static const double _markerAmplitude = 0.15;
  static const int _markerSilenceAfterMs = 20;

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
    // Use ULTRASONIC marker injection
    final refPath = await _materializeRefWithUltrasonicMarker(refAssetPath);
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
    
    // --- SIGNAL ANALYSIS & ALIGNMENT (ULTRASONIC) ---
    _log('Starting ultrasonic analysis...');

    int bestLagRef = -1;
    int bestLagRec = -1;
    double confidenceRec = 0.0;
    
    File? recRawFile;
    if (_rawWavPath != null) {
      recRawFile = File(_rawWavPath!);
    }
    
    // We also need the REFERENCE WAV used for playback (which has the marker)
    // _lastRefAssetPath is the asset... wait, we need the materialized file path?
    // We returned it in startRun but didn't store it class-level?
    // Ah, we regenerate the expected marker waveform in memory, we don't need to read the file 
    // if we trust we generated it at the start.
    // BUT, for the reference signal "truth", we ideally read the file we played or just assume 
    // the marker is at sample 0 (since we prepended it).
    // The prompt says: "detect that chirp in both the reference and the recorded WAV".
    
    // So we need to re-materialize or keep the path of the ref file we played? 
    // Or just look at the asset? No, the asset doesn't have the marker.
    // We probably regenerated it in _materializeRefWithUltrasonicMarker.
    // Let's assume marker is at 0 in Ref for simplicity (we prepended it), 
    // OR scanning the materialized file is safer if we want to be purist.
    // The prompt explicitly says: "detect that chirp in both ... via cross-correlation".
    
    // Let's find the ref file. We don't save the path in class state currently. 
    // It's in the temp dir as 'ref_with_marker.wav'.
    final dir = await getTemporaryDirectory();
    final refFilePath = '${dir.path}/ref_with_marker.wav';
    final refFile = File(refFilePath);
    
    if (recRawFile != null && recRawFile.existsSync() && refFile.existsSync()) {
        final recBytes = await recRawFile.readAsBytes();
        final refBytes = await refFile.readAsBytes();
        
        // Config for detection
        final needle = UltrasonicMarker.generateChirpWaveform(
          sampleRate: _sampleRate, 
          startHz: _markerStartHz, 
          endHz: _markerEndHz, 
          durationMs: _markerDurationMs
        );
        
        // Search Ref (first 0.5s)
        final resRef = _findMarkerLag(
           pcmBytes: refBytes.sublist(44), // skip header
           needle: needle,
           maxSearchSeconds: 0.5,
        );
        bestLagRef = resRef.bestLag;
        
        // Search Rec (first 2.0s)
        final resRec = _findMarkerLag(
           pcmBytes: recBytes.sublist(44), // skip header
           needle: needle,
           maxSearchSeconds: 2.0,
        );
        bestLagRec = resRec.bestLag;
        confidenceRec = resRec.confidence;
        
        _log('Correlation Results:');
        _log('  Ref: lag=$bestLagRef, conf=${resRef.confidence.toStringAsFixed(2)}');
        _log('  Rec: lag=$bestLagRec, conf=${resRec.confidence.toStringAsFixed(2)}');
    }

    _alignedWavPath = null;
    AlignmentStrategy strategy = AlignmentStrategy.noAlignmentPossible;
    double offsetSec = 0.0;
    
    // Confidence threshold
    const double minConfidence = 6.0;

    if (bestLagRef != -1 && bestLagRec != -1 && confidenceRec >= minConfidence) {
       // Offset: Rec - Ref
       final diffSamples = bestLagRec - bestLagRef;
       offsetSec = diffSamples / _sampleRate;
       
       _log('Offset calculated (ultrasonic): $diffSamples samples ($offsetSec sec)');
       
       final dir = await getTemporaryDirectory();
       _alignedWavPath = '${dir.path}/sync_aligned.wav';
       
       try {
         if (offsetSec > 0) {
           // Recorder LATE -> Trim Rec start
           await _trimStartOfWav(
              inputPath: _rawWavPath!,
              outputPath: _alignedWavPath!,
              trimSeconds: offsetSec, 
           );
           strategy = AlignmentStrategy.signalAnalysis;
           _log('Aligned by trimming ${offsetSec}s.');
         } else {
           // Recorder EARLY -> Pad Rec start
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
      _log('Marker detection FAILED or LOW CONFIDENCE. (conf=$confidenceRec < $minConfidence)');
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

  /// Standard asset materialization (NO MARKER) for playback
  Future<String> _materializeAssetToFile(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    final buffer = byteData.buffer;
    final tempDir = await getTemporaryDirectory();
    final tempPath = '${tempDir.path}/${assetPath.split('/').last}';
    await File(tempPath).writeAsBytes(
        buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    return tempPath;
  }

  /// INJECTS ULTRASONIC MARKER at the start.
  Future<String> _materializeRefWithUltrasonicMarker(String assetPath) async {
    // 1. Load asset bytes
    final assetByteData = await rootBundle.load(assetPath);
    final assetBytes = assetByteData.buffer.asUint8List();
    
    // 2. Generate Marker
    final markerPcm = UltrasonicMarker.buildUltrasonicChirpPcm16(
      sampleRate: _sampleRate, 
      startHz: _markerStartHz, 
      endHz: _markerEndHz, 
      durationMs: _markerDurationMs, 
      amplitude: _markerAmplitude,
      silenceAfterMs: _markerSilenceAfterMs,
    );
    
    // 3. Assemble
    // Assume asset has 44 byte header. We strip it.
    int assetHeaderLen = 44;
    if (assetBytes.length < 44) assetHeaderLen = 0; // fallback
    
    final assetPcm = assetBytes.sublist(assetHeaderLen);
    
    final totalLen = markerPcm.length + assetPcm.length;
    final header = _buildWavHeader(totalLen, _sampleRate, _numChannels);
    
    final bb = BytesBuilder();
    bb.add(header);
    bb.add(markerPcm);
    bb.add(assetPcm);
    
    // Write to temp
    final dir = await getTemporaryDirectory();
    const fileName = 'ref_with_marker.wav';
    final tempFile = File('${dir.path}/$fileName');
    await tempFile.writeAsBytes(bb.toBytes());
    
    return tempFile.path;
  }
  
  // --- Correlation Helper ---
  
  _CorrelationResult _findMarkerLag({
    required Uint8List pcmBytes, 
    required List<double> needle, 
    required double maxSearchSeconds
  }) {
      final numSamples = pcmBytes.length ~/ 2;
      final maxSearchSamples = (maxSearchSeconds * _sampleRate).round();
      final searchLen = (numSamples < maxSearchSamples) ? numSamples : maxSearchSamples;
      
      final needleLen = needle.length;
      if (searchLen < needleLen) return _CorrelationResult(-1, 0.0);
      
      // Extract signal to doubles for easier math
      // (Optimization: only convert what we scan? But we scan sliding window.)
      // We need signal up to searchLen + needleLen ideally to scan full needle at last position.
      // Scan limit is start index.
      final scanLimit = searchLen - needleLen;
      
      final signal = List<double>.filled(searchLen, 0.0);
      final bd = ByteData.sublistView(pcmBytes);
      for (int i=0; i<searchLen; i++) {
         signal[i] = bd.getInt16(i*2, Endian.little) / 32768.0;
      }
      
      double bestCorr = -1.0;
      int bestLag = -1;
      
      double sumAbsCorr = 0.0;
      int countCorr = 0;
      
      for (int lag=0; lag < scanLimit; lag++) {
         double dot = 0.0;
         for (int j=0; j < needleLen; j++) {
            dot += signal[lag+j] * needle[j];
         }
         final absDot = dot.abs();
         
         if (absDot > bestCorr) {
            bestCorr = absDot;
            bestLag = lag;
         }
         
         sumAbsCorr += absDot;
         countCorr++;
      }
      
      double confidence = 0.0;
      if (countCorr > 0 && sumAbsCorr > 0) {
         final mean = sumAbsCorr / countCorr;
         confidence = bestCorr / mean;
      }
      
      return _CorrelationResult(bestLag, confidence);
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
class _CorrelationResult {
  final int bestLag;
  final double confidence;
  _CorrelationResult(this.bestLag, this.confidence);
}
