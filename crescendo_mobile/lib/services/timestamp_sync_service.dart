import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

// NEW
import 'package:flutter_sound/flutter_sound.dart';

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
  final StreamController<Food> _recFoodController = StreamController<Food>.broadcast();

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
    if (!_isInited) await init();

    _logs.clear();
    _refStartNs = 0;
    _recStartNs = 0;

    _lastRefAssetPath = refAssetPath;
    _rawWavPath = null;
    _alignedWavPath = null;

    // Cancel old subs
    await _refProgSub?.cancel();
    _refProgSub = null;
    await _recStreamSub?.cancel();
    _recStreamSub = null;

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

    // 2) Start recorder -> toFile WAV PCM16 (stable for trimming/padding)
    // ALSO record to a stream so we can timestamp first chunk reliably:
    // flutter_sound streams are delivered as "FoodData" inside "Food".
    // We set _recStartNs on the first FoodData we see.

    // Start recorder: write WAV to file
    // Codec.pcm16WAV => you get a valid .wav with PCM16 (no manual PCM->WAV step).
    await _recorder.startRecorder(
      toFile: _rawWavPath,
      codec: Codec.pcm16WAV,
      sampleRate: _sampleRate,
      numChannels: _numChannels,
    );
    _log('Recorder started (toFile WAV).');

    // Timestamp immediately since we aren't streaming
    if (_recStartNs == 0) {
      _recStartNs = _monoNs();
      _log('Rec started at $_recStartNs ns');
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

  Future<SyncRunResult> stopRunAndAlign() async {
    _log('Stopping...');

    // Stop ref playback
    if (_playerRef.isPlaying) {
      await _playerRef.stopPlayer();
    }

    // Stop recorder
    if (_recorder.isRecording) {
      await _recorder.stopRecorder();
    }

    // Cancel subs
    await _refProgSub?.cancel();
    _refProgSub = null;
    await _recStreamSub?.cancel();
    _recStreamSub = null;

    if (_rawWavPath == null) throw Exception('No recording path.');
    _log('Stopped. rawWav=$_rawWavPath');

    // Ensure we captured recStartNs
    if (_recStartNs == 0) {
      _recStartNs = _monoNs();
      _log('WARNING: No first-chunk timestamp; fallback recStartNs=$_recStartNs');
    }
    if (_refStartNs == 0) {
      _refStartNs = _monoNs();
      _log('WARNING: No ref timestamp; fallback refStartNs=$_refStartNs');
    }

    final diffNs = _recStartNs - _refStartNs;
    final offsetSec = diffNs / 1e9;
    _log('Offset calculated: $offsetSec sec (${diffNs / 1e6} ms)');

    final silenceToPrepend = offsetSec > 0 ? offsetSec : 0.0;

    AlignmentStrategy strategy = AlignmentStrategy.noAlignmentPossible;
    String alignedPath = _rawWavPath!;

    // Prepend silence if offset positive; else we’ll do runtime delay.
    if (silenceToPrepend > 0) {
      try {
        alignedPath = await _prependSilenceToWav(_rawWavPath!, silenceToPrepend);
        strategy = AlignmentStrategy.prependSilenceToRecordingWav;
        _alignedWavPath = alignedPath;
        _log('Aligned wav written: $alignedPath');
      } catch (e) {
        _log('WAV prepend failed: $e');
        strategy = AlignmentStrategy.fallbackDelayReferencePlayback;
        _alignedWavPath = null;
      }
    } else {
      strategy = AlignmentStrategy.fallbackDelayReferencePlayback;
      _alignedWavPath = null;
      _log('Negative/zero offset => runtime delay strategy.');
    }

    return SyncRunResult(
      refStartNs: _refStartNs,
      recStartNs: _recStartNs,
      offsetSec: offsetSec,
      silencePrependedSec: silenceToPrepend,
      rawRecordingPath: _rawWavPath!,
      alignedRecordingPath: alignedPath,
      strategy: strategy,
      logs: List.from(_logs),
    );
  }

  Future<void> playAligned() async {
    if (_lastRefAssetPath == null || _rawWavPath == null) return;

    await _applyMuteVolumes();

    // Prepare sources
    final refPath = await _materializeAssetToFile(_lastRefAssetPath!);
    final recPath = _alignedWavPath ?? _rawWavPath!;

    final diffNs = _recStartNs - _refStartNs;
    final offsetSec = diffNs / 1e9;

    // Stop any prior playback
    if (_playerRef.isPlaying) await _playerRef.stopPlayer();
    if (_playerRec.isPlaying) await _playerRec.stopPlayer();

    if (_alignedWavPath != null) {
      // Aligned file exists => start both immediately
      _log('Playing both immediately (aligned WAV exists).');
      await _playerRef.startPlayer(fromURI: refPath, whenFinished: () {});
      await _playerRec.startPlayer(fromURI: recPath, whenFinished: () {});
      return;
    }

    // Runtime delay fallback
    if (offsetSec >= 0) {
      // recording started later -> delay rec
      _log('Runtime delay: Ref now, Rec after ${offsetSec.toStringAsFixed(4)}s');
      await _playerRef.startPlayer(fromURI: refPath, whenFinished: () {});
      Future.delayed(Duration(milliseconds: (offsetSec * 1000).round()), () async {
        await _applyMuteVolumes();
        await _playerRec.startPlayer(fromURI: recPath, whenFinished: () {});
      });
    } else {
      // recording started earlier -> delay ref
      _log('Runtime delay: Rec now, Ref after ${(-offsetSec).toStringAsFixed(4)}s');
      await _playerRec.startPlayer(fromURI: recPath, whenFinished: () {});
      Future.delayed(Duration(milliseconds: ((-offsetSec) * 1000).round()), () async {
        await _applyMuteVolumes();
        await _playerRef.startPlayer(fromURI: refPath, whenFinished: () {});
      });
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

  Future<String> _prependSilenceToWav(String originalPath, double seconds) async {
    final bytes = await File(originalPath).readAsBytes();
    final bd = bytes.buffer.asByteData();

    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') {
      throw Exception('Not a RIFF WAV');
    }

    // Find fmt
    int fmtOffset = 12;
    while (fmtOffset + 8 < bytes.length &&
        String.fromCharCodes(bytes.sublist(fmtOffset, fmtOffset + 4)) != 'fmt ') {
      fmtOffset++;
      if (fmtOffset > 256) throw Exception('fmt chunk not found');
    }

    final fmtSize = bd.getUint32(fmtOffset + 4, Endian.little);
    final audioFormat = bd.getUint16(fmtOffset + 8, Endian.little);
    final numChannels = bd.getUint16(fmtOffset + 10, Endian.little);
    final sampleRate = bd.getUint32(fmtOffset + 12, Endian.little);
    final bitsPerSample = bd.getUint16(fmtOffset + 22, Endian.little);

    if (audioFormat != 1) throw Exception('WAV not PCM16 (format=$audioFormat)');

    // Find data
    int dataOffset = fmtOffset + 8 + fmtSize;
    while (dataOffset + 8 < bytes.length &&
        String.fromCharCodes(bytes.sublist(dataOffset, dataOffset + 4)) != 'data') {
      final size = bd.getUint32(dataOffset + 4, Endian.little);
      dataOffset += 8 + size;
    }
    if (String.fromCharCodes(bytes.sublist(dataOffset, dataOffset + 4)) != 'data') {
      throw Exception('data chunk not found');
    }

    final oldDataSize = bd.getUint32(dataOffset + 4, Endian.little);
    final bytesPerSample = bitsPerSample ~/ 8;
    final frameSize = numChannels * bytesPerSample;

    final framesToAdd = (seconds * sampleRate).round();
    final bytesToAdd = framesToAdd * frameSize;

    final newPath = originalPath.replaceAll('.wav', '_aligned.wav');
    final out = await File(newPath).open(mode: FileMode.write);

    // RIFF + new size
    await out.writeFrom(bytes.sublist(0, 4));
    final oldFileSize = bytes.length - 8;
    final newFileSize = oldFileSize + bytesToAdd;
    final sizeBytes = Uint8List(4)
      ..buffer.asByteData().setUint32(0, newFileSize, Endian.little);
    await out.writeFrom(sizeBytes);

    // Copy everything up through "data"
    await out.writeFrom(bytes.sublist(8, dataOffset + 4));

    // New data size
    final newDataSize = oldDataSize + bytesToAdd;
    final dataSizeBytes = Uint8List(4)
      ..buffer.asByteData().setUint32(0, newDataSize, Endian.little);
    await out.writeFrom(dataSizeBytes);

    // Silence + old PCM
    await out.writeFrom(Uint8List(bytesToAdd));
    await out.writeFrom(bytes.sublist(dataOffset + 8));

    await out.close();
    return newPath;
  }

  Future<void> dispose() async {
    await _refProgSub?.cancel();
    await _recStreamSub?.cancel();
    await _recFoodController.close();

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