import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logger/logger.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

// NEW
import 'package:flutter_sound/flutter_sound.dart';
import 'pitch_isolate_processor.dart';
import 'chirp_marker.dart';

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
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder(logLevel: Level.nothing);
  final FlutterSoundPlayer _playerRef = FlutterSoundPlayer(logLevel: Level.nothing);
  final FlutterSoundPlayer _playerRec = FlutterSoundPlayer(logLevel: Level.nothing);

  // State
  bool _isInited = false;
  bool _isArmed = false;

  String? _rawWavPath;
  String? _alignedWavPath;
  String? _mixedWavPath; // NEW: Mixed output

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

    // Explicitly silence logs (constructor param sometimes ignored)
    _recorder.setLogLevel(Level.nothing);
    _playerRef.setLogLevel(Level.nothing);
    _playerRec.setLogLevel(Level.nothing);

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

  // Marker config (Chirp)
  // Configured in ChirpMarker defaults, but we use constants here to be explicit if needed
  // or just rely on the helper defaults.
  // We track where we *expect* the marker to be in the reference file (usually 0)

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
    // INJECT ROBUST CHIRP MARKER
    final refPath = await _materializeRefWithMarker(refAssetPath);
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
    
    // --- SIGNAL ANALYSIS & ALIGNMENT (CHIRP + CORRELATION) ---
    _log('Starting chirp alignment...');

    File? recRawFile;
    if (_rawWavPath != null) {
      recRawFile = File(_rawWavPath!);
    }
    
    // We need the reference file we played (which has the marker at the start)
    // We don't store the path, but we know it's 'ref_with_marker.wav' in temp
    final dir = await getTemporaryDirectory();
    final refFilePath = '${dir.path}/ref_with_marker.wav';
    final refFile = File(refFilePath);
    
    int bestLagRef = -1;
    int bestLagRec = -1;
    double confidenceRec = 0.0;
    
    if (recRawFile != null && recRawFile.existsSync() && refFile.existsSync()) {
        final recBytes = await recRawFile.readAsBytes();
        final refBytes = await refFile.readAsBytes();
        
        // Generate needle
        final needle = ChirpMarker.generateChirpWaveform(); // use defaults
        
        // Config detection
        // Ref: search 0.5s
        final resRef = _detectMarker(
          wavBytes: refBytes,
          marker: needle,
          searchStartSamples: 0,
          searchLenSamples: (0.5 * _sampleRate).round(),
        );
        bestLagRef = resRef.bestLag;
        
        // Rec: search 2.0s
        final resRec = _detectMarker(
          wavBytes: recBytes,
          marker: needle,
          searchStartSamples: 0,
          searchLenSamples: (2.0 * _sampleRate).round(),
        );
        bestLagRec = resRec.bestLag;
        confidenceRec = resRec.confidence;
        
        _log('Correlation Results:');
        _log('  Ref: lag=$bestLagRef, conf=${resRef.confidence.toStringAsFixed(2)}');
        _log('  Rec: lag=$bestLagRec, conf=${resRec.confidence.toStringAsFixed(2)}');
    }

    _alignedWavPath = null;
    AlignmentStrategy strategy = AlignmentStrategy.noAlignmentPossible;
    int offsetSamples = 0;
    double offsetSec = 0.0;
    const double minConfidence = 6.0;

    if (bestLagRef != -1 && bestLagRec != -1 && confidenceRec >= minConfidence) {
       offsetSamples = bestLagRec - bestLagRef;
       offsetSec = offsetSamples / _sampleRate;
       
       _log('Offset: $offsetSamples samples ($offsetSec sec)');
       
       final dir = await getTemporaryDirectory();
       _alignedWavPath = '${dir.path}/sync_aligned.wav';
       
       try {
         if (offsetSamples > 0) {
           // Recorder LATE -> Trim start
           await _trimStartOfWavSamples(
             inputPath: _rawWavPath!, 
             outputPath: _alignedWavPath!, 
             trimSamples: offsetSamples
           );
           strategy = AlignmentStrategy.signalAnalysis;
           _log('Aligned by trimming $offsetSamples samples.');
         } else {
           // Recorder EARLY -> Pad start
           final padSamples = -offsetSamples;
           await _prependSilenceToWavSamples(
             _rawWavPath!, 
             _alignedWavPath!, 
             padSamples
           );
           strategy = AlignmentStrategy.signalAnalysis;
           _log('Aligned by padding $padSamples samples.');
         }
       } catch (e) {
          _log('Alignment failed: $e');
          _alignedWavPath = null;
       }
    } else {
      _log('Marker detection FAILED or LOW CONFIDENCE. (conf=$confidenceRec < $minConfidence)');
    }
    
    // MIXING
    // We mix the REF (with marker, as played) + ALIGNED REC (which has marker captured)
    // This allows audible verification of alignment.
    _mixedWavPath = null;
    if (_alignedWavPath != null && refFile.existsSync()) {
      try {
         _mixedWavPath = await _mixAlignedWavs(
            refWavPath: refFile.path, 
            recAlignedWavPath: _alignedWavPath!
         );
         _log('Mixed WAV created: $_mixedWavPath');
      } catch (e) {
         _log('Mixing failed: $e');
      }
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
    
    // Prefer mixed, then aligned, then raw
    String? path = _mixedWavPath ?? _alignedWavPath ?? _rawWavPath;
    
    if (path == null) {
       _log('No file to play.');
       return;
    }
    
    if (!File(path).existsSync()) {
       _log('File missing: $path');
       return;
    }

    // Stop any prior playback
    if (_playerRef.isPlaying) await _playerRef.stopPlayer();
    if (_playerRec.isPlaying) await _playerRec.stopPlayer();
    
    // Single player playback
    _log('Playing mixed/monolithic file: $path');
    try {
      // Use playerRef as the main player
      await _playerRef.startPlayer(
         fromURI: path,
         whenFinished: () => _log('Playback finished.'),
      );
    } catch (e) {
      _log('Error starting playback: $e');
    }
  }

  /// INJECTS CHIRP MARKER at the start.
  Future<String> _materializeRefWithMarker(String assetPath) async {
    // 1. Load asset bytes
    final assetByteData = await rootBundle.load(assetPath);
    final assetBytes = assetByteData.buffer.asUint8List();
    
    // 2. Generate Marker
    final markerPcm = ChirpMarker.buildChirpPcm16(); // defaults
    
    // 3. Assemble
    int assetHeaderLen = 44;
    if (assetBytes.length < 44) assetHeaderLen = 0; 
    
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
  
  // Scans using cross-correlation (matched filter)
  _CorrelationResult _detectMarker({
    required Uint8List wavBytes,
    required Float32List marker,
    required int searchStartSamples,
    required int searchLenSamples,
  }) {
    // Skip 44 byte header
    const pcmOffset = 44;
     if (wavBytes.length < pcmOffset) return const _CorrelationResult(-1, 0.0);
     
     final numTotalSamples = (wavBytes.length - pcmOffset) ~/ 2;
     if (numTotalSamples <= 0) return const _CorrelationResult(-1, 0.0);
 
     // Bounds
     int start = searchStartSamples;
     if (start >= numTotalSamples) start = numTotalSamples - 1;
     
     int end = start + searchLenSamples;
     if (end > numTotalSamples) end = numTotalSamples;
     
     final markerLen = marker.length;
     final scanLimit = end - markerLen;
     
     if (scanLimit <= start) return const _CorrelationResult(-1, 0.0);
    
    // Just loop and compute dot product
    // Optimization: could normalize signal window, but dot product is sufficient for peak finding usually?
    // User requested: "confidence = bestCorr / (meanAbsCorr + 1e-9)"
    // So we track abs corr.
    
    final bd = ByteData.sublistView(wavBytes);
    
    double bestCorr = -1.0;
    int bestLag = -1;
    double sumAbsCorr = 0.0;
    int count = 0;
    
    // Pre-convert signal window to float to avoid doing it inside inner loop repeatedly?
    // Or just do it on the fly window sliding?
    // "Convert a sliding window of signal to float on the fly"
    // To do efficiently: 
    // Actually, we can just convert the search region to float[] once.
    // Search region size ~ 2s * 48k = 96k samples. Cheap.
    final regionLen = end - start;
    final signalRegion = Float32List(regionLen);
    
    for (int i=0; i<regionLen; i++) {
       final sampIndex = start + i;
       final s16 = bd.getInt16(pcmOffset + sampIndex*2, Endian.little);
       signalRegion[i] = s16 / 32767.0; // normalize roughly
    }
    
    // Now scan signalRegion
    final loopLimit = regionLen - markerLen;
    
    for (int lag=0; lag < loopLimit; lag++) {
       double dot = 0.0;
       for (int m=0; m < markerLen; m++) {
          dot += signalRegion[lag+m] * marker[m];
       }
       
       // dot is correlation
       // We might want abs(dot) if phase flip possible? Usually signals are synced phase-wise.
       // Let's use dot (raw correlation) for peak finding, assuming phase alignment.
       // But wait, "meanAbsCorr" implies we track magnitude.
       // If dot is negative, it's anti-correlated.
       // A chirp match should be positive strong peak.
       
       if (dot > bestCorr) {
          bestCorr = dot;
          bestLag = start + lag;
       }
       
       sumAbsCorr += dot.abs();
       count++;
    }
    
    double confidence = 0.0;
    if (count > 0) {
       final mean = sumAbsCorr / count;
       confidence = bestCorr / (mean + 1e-9);
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
  
  // --- WAV Helpers (Samples) ---

  Future<void> _trimStartOfWavSamples({required String inputPath, required String outputPath, required int trimSamples}) async {
     final inputFile = File(inputPath);
     final bytes = await inputFile.readAsBytes();
     if (bytes.length < 44) return;
     
     final blockAlign = _numChannels * 2;
     final trimBytes = trimSamples * blockAlign; // sample * channels * 2
     
     // Skip original header
     if (44 + trimBytes >= bytes.length) {
       final header = _buildWavHeader(0, _sampleRate, _numChannels);
       await File(outputPath).writeAsBytes(header);
       return;
     }

     final newLength = (bytes.length - 44) - trimBytes;
     // Re-check alignment? Block align is 2 or 4.
     
     final header = _buildWavHeader(newLength, _sampleRate, _numChannels);
     
     final outBytes = BytesBuilder();
     outBytes.add(header);
     outBytes.add(bytes.sublist(44 + trimBytes));
     
     await File(outputPath).writeAsBytes(outBytes.toBytes());
  }

  Future<void> _prependSilenceToWavSamples(String inputPath, String outputPath, int silenceSamples) async {
    final inFile = File(inputPath);
    final bytes = await inFile.readAsBytes();
    
    final blockAlign = _numChannels * 2;
    final silenceBytesCount = silenceSamples * blockAlign;
    
    final currentDataLen = (bytes.length >= 44) ? bytes.length - 44 : 0;
    final newDataLen = currentDataLen + silenceBytesCount;
    
    final header = _buildWavHeader(newDataLen, _sampleRate, _numChannels);
    final silence = Uint8List(silenceBytesCount); 
    
    final bb = BytesBuilder();
    bb.add(header);
    bb.add(silence);
    if (bytes.length > 44) {
      bb.add(bytes.sublist(44));
    }
    
    await File(outputPath).writeAsBytes(bb.toBytes());
  }

  // --- MIXING HELPER ---

  Future<String> _mixAlignedWavs({
     required String refWavPath,
     required String recAlignedWavPath,
     double refGain = 1.0,
     double recGain = 1.0,
  }) async {
      final fRef = File(refWavPath);
      final fRec = File(recAlignedWavPath);
      
      final bytesRef = await fRef.readAsBytes();
      final bytesRec = await fRec.readAsBytes();
      
      // Skip headers (44 bytes implied)
      int offRef = 44;
      int offRec = 44;
      if (bytesRef.length < 44) offRef = 0;
      if (bytesRec.length < 44) offRec = 0;
      
      final bdRef = ByteData.sublistView(bytesRef);
      final bdRec = ByteData.sublistView(bytesRec);
      
      final lenRef = (bytesRef.length - offRef) ~/ 2;
      final lenRec = (bytesRec.length - offRec) ~/ 2;
      
      final maxLen = (lenRef > lenRec) ? lenRef : lenRec;
      
      _log('Mixing: Ref($lenRef samps) + Rec($lenRec samps) -> $maxLen samps');
      
      // Prepare output buffer
      final outBytesCount = maxLen * 2;
      final outData = Uint8List(outBytesCount);
      final bdOut = ByteData.sublistView(outData);
      
      for (int i=0; i < maxLen; i++) {
         int sRef = 0;
         int sRec = 0;
         
         if (i < lenRef) {
            sRef = bdRef.getInt16(offRef + i*2, Endian.little);
         }
         
         if (i < lenRec) {
            sRec = bdRec.getInt16(offRec + i*2, Endian.little);
         }
         
         // Mix
         double mixed = (sRef * refGain) + (sRec * recGain);
         
         // Clamp
         if (mixed > 32767) mixed = 32767;
         if (mixed < -32768) mixed = -32768;
         
         bdOut.setInt16(i*2, mixed.round(), Endian.little);
      }
      
      // Build WAV
      final header = _buildWavHeader(outBytesCount, _sampleRate, _numChannels);
      final bb = BytesBuilder();
      bb.add(header);
      bb.add(outData);
      
      final dir = await getTemporaryDirectory();
      final outPath = '${dir.path}/sync_mixed.wav';
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
  const _CorrelationResult(this.bestLag, this.confidence);
}
