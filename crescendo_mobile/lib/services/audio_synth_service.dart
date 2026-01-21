import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wav/wav.dart';

import '../models/reference_note.dart';

class AudioSynthService {
  static const double tailSeconds = 1.0;
  final int sampleRate;
  final AudioPlayer _player;
  final AudioPlayer?
      _secondaryPlayer; // For mixing reference notes with recorded audio
  String? _secondaryPreparedPath; // Track which file secondary player is prepared for
  bool _secondaryPrepared = false;

  AudioSynthService({this.sampleRate = 44100, bool enableMixing = false})
      : _player = AudioPlayer(),
        _secondaryPlayer = enableMixing ? AudioPlayer() : null {
    _player.setReleaseMode(ReleaseMode.stop);
    final secondary = _secondaryPlayer;
    if (secondary != null) {
      secondary.setReleaseMode(ReleaseMode.stop);
      _applyAudioContextToPlayer(secondary);
    }
    _applyAudioContext();
  }

  Future<String> renderReferenceNotes(List<ReferenceNote> notes) async {
    // Convert ReferenceNote to serializable format for isolate
    final noteData = notes
        .map((n) => {
              'startSec': n.startSec,
              'endSec': n.endSec,
              'midi': n.midi,
            })
        .toList();

    // Generate samples in isolate (heavy CPU work)
    // This PerfTrace breakdown will show the isolate work is off UI thread
    final samples = await compute(_generateSamplesInIsolate, {
      'notes': noteData,
      'sampleRate': sampleRate,
      'tailSeconds': tailSeconds,
    });

    // Convert to WAV and write file (lightweight I/O)
    final bytes = _toWav(samples);
    final dir = await getTemporaryDirectory();
    final path = p.join(
        dir.path, 'pitch_highway_${DateTime.now().millisecondsSinceEpoch}.wav');
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Isolate function for sample generation (pure function, no side effects)
  static List<double> _generateSamplesInIsolate(Map<String, dynamic> params) {
    final noteData = params['notes'] as List<Map<String, dynamic>>;
    final sampleRate = params['sampleRate'] as int;
    final tailSeconds = params['tailSeconds'] as double;

    final samples = <double>[];
    double cursor = 0;
    Map<String, dynamic>? lastNote;
    double lastNoteDur = 0.0;

    for (final n in noteData) {
      final startSec = n['startSec'] as double;
      final endSec = n['endSec'] as double;
      final midi = (n['midi'] as num).toDouble();

      if (startSec > cursor) {
        final gapFrames = ((startSec - cursor) * sampleRate).toInt();
        samples.addAll(List.filled(gapFrames, 0.0));
        cursor = startSec;
      }
      final dur = max(0.01, endSec - startSec);
      final frames = (dur * sampleRate).toInt();
      final hz = 440.0 * pow(2.0, (midi - 69.0) / 12.0);
      for (var f = 0; f < frames; f++) {
        samples.add(_pianoSampleStatic(hz, f / sampleRate));
      }
      cursor = endSec;
      lastNote = n;
      lastNoteDur = dur;
    }
    if (lastNote != null) {
      final midi = (lastNote['midi'] as num).toDouble();
      final hz = 440.0 * pow(2.0, (midi - 69.0) / 12.0);
      final releaseFrames = (tailSeconds * sampleRate).toInt();
      for (var f = 0; f < releaseFrames; f++) {
        final t = lastNoteDur + f / sampleRate;
        final fade = 1.0 - (f / releaseFrames);
        samples.add(_pianoSampleStatic(hz, t) * fade);
      }
    }
    if (samples.isEmpty) {
      final frames = (0.1 * sampleRate).toInt();
      samples.addAll(List.filled(frames, 0.0));
    }

    return samples;
  }

  /// Static version of _pianoSample for use in isolate
  static double _pianoSampleStatic(double hz, double noteTime) {
    // Simple additive "piano-ish" timbre: fast attack with exponential decay.
    final attack = (noteTime / 0.02).clamp(0.0, 1.0);
    final decay = exp(-3.0 * noteTime);
    final env = attack * decay;
    final fundamental = sin(2 * pi * hz * noteTime);
    final harmonic2 = 0.6 * sin(2 * pi * hz * 2 * noteTime);
    final harmonic3 = 0.3 * sin(2 * pi * hz * 3 * noteTime);
    final harmonic4 = 0.15 * sin(2 * pi * hz * 4 * noteTime);
    return 0.45 * env * (fundamental + harmonic2 + harmonic3 + harmonic4);
  }

  Future<void> playFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return;
    final size = await file.length();
    if (size <= 0) return;
    await _player.stop();
    await _applyAudioContext();
    await _player.setVolume(1.0);
    
    // Detect MIME type from file extension
    String mimeType = 'audio/wav';
    if (path.toLowerCase().endsWith('.m4a')) {
      mimeType = 'audio/mp4';
    } else if (path.toLowerCase().endsWith('.mp3')) {
      mimeType = 'audio/mpeg';
    } else if (path.toLowerCase().endsWith('.wav')) {
      mimeType = 'audio/wav';
    }
    
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;
      await _player.setSourceBytes(bytes, mimeType: mimeType);
      await _player.resume();
    } on PlatformException {
      await _player.play(DeviceFileSource(path, mimeType: mimeType));
    } on AudioPlayerException {
      await _player.play(DeviceFileSource(path, mimeType: mimeType));
    }
  }

  /// Play a secondary audio file simultaneously with the primary player.
  /// Used for mixing reference notes with recorded audio in review mode.
  Future<void> playSecondaryFile(String path) async {
    final player = _secondaryPlayer;
    if (player == null) return;
    final file = File(path);
    if (!await file.exists()) return;
    final size = await file.length();
    if (size <= 0) return;
    await player.stop();
    await player.setVolume(1.0);
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;
      await player.setSourceBytes(bytes, mimeType: 'audio/wav');
      await player.resume();
    } on PlatformException {
      await player.play(DeviceFileSource(path, mimeType: 'audio/wav'));
    } on AudioPlayerException {
      await player.play(DeviceFileSource(path, mimeType: 'audio/wav'));
    }
  }

  Stream<void> get onComplete => _player.onPlayerComplete;
  Stream<Duration> get onPositionChanged => _player.onPositionChanged;
  Stream<PlayerState> get onPlayerStateChanged => _player.onPlayerStateChanged;

  Future<Duration?> getCurrentPosition() => _player.getCurrentPosition();

  /// Seek the primary player to a specific position (with timeout protection)
  Future<bool> seek(Duration position, {int? runId, Duration timeout = const Duration(seconds: 2)}) async {
    final state = _player.state;
    final hasSource = _player.source != null;
    final targetSec = position.inMilliseconds / 1000.0;
    
    debugPrint('[AudioSynthService] seek: which=primary targetSec=$targetSec hasSource=$hasSource playing=${state == PlayerState.playing} state=$state runId=$runId');
    
    try {
      await _player.seek(position).timeout(
        timeout,
        onTimeout: () {
          debugPrint('[AudioSynthService] seek: TIMEOUT after ${timeout.inMilliseconds}ms runId=$runId');
          throw TimeoutException('seek timeout', timeout);
        },
      );
      
      // Get position after seek for logging
      final pos = await _player.getCurrentPosition();
      debugPrint('[AudioSynthService] seek: done posMs=${pos?.inMilliseconds} runId=$runId');
      
      return true;
    } catch (e) {
      debugPrint('[AudioSynthService] seek: error $e runId=$runId');
      return false;
    }
  }

  /// Ensure secondary player is prepared for a specific file (iOS workaround)
  /// Must be called before seekSecondary to avoid timeouts
  Future<bool> ensureSecondaryPrepared(String path, {int? runId}) async {
    final player = _secondaryPlayer;
    if (player == null) {
      debugPrint('[AudioSynthService] ensureSecondaryPrepared: no secondary player');
      return false;
    }

    // If already prepared for this file, skip
    if (_secondaryPrepared && _secondaryPreparedPath == path) {
      debugPrint('[AudioSynthService] ensureSecondaryPrepared: already prepared for $path runId=$runId');
      return true;
    }

    try {
      debugPrint('[AudioSynthService] ensureSecondaryPrepared: preparing $path runId=$runId');
      
      // Stop and reset
      await player.stop();
      _secondaryPrepared = false;
      _secondaryPreparedPath = null;

      // Set source
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('[AudioSynthService] ensureSecondaryPrepared: file not found $path runId=$runId');
        return false;
      }

      await player.setVolume(1.0);
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          debugPrint('[AudioSynthService] ensureSecondaryPrepared: empty file $path runId=$runId');
          return false;
        }
        await player.setSourceBytes(bytes, mimeType: 'audio/wav');
      } on PlatformException {
        await player.play(DeviceFileSource(path, mimeType: 'audio/wav'));
      } on AudioPlayerException {
        await player.play(DeviceFileSource(path, mimeType: 'audio/wav'));
      }

      // Wait for player to be ready
      await Future.delayed(const Duration(milliseconds: 100));

      // iOS warm-up: resume briefly then pause
      if (Platform.isIOS) {
        await player.resume();
        await Future.delayed(const Duration(milliseconds: 50));
        await player.pause();
        await Future.delayed(const Duration(milliseconds: 50));
      }

      _secondaryPrepared = true;
      _secondaryPreparedPath = path;
      
      // Get duration for logging
      final duration = await player.getDuration();
      debugPrint('[AudioSynthService] ensureSecondaryPrepared: ready durationMs=${duration?.inMilliseconds} runId=$runId');
      
      return true;
    } catch (e) {
      debugPrint('[AudioSynthService] ensureSecondaryPrepared: error $e runId=$runId');
      _secondaryPrepared = false;
      _secondaryPreparedPath = null;
      return false;
    }
  }

  /// Seek the secondary player with timeout (non-blocking)
  Future<bool> seekSecondary(Duration position, {int? runId, Duration timeout = const Duration(seconds: 2)}) async {
    final player = _secondaryPlayer;
    if (player == null) {
      debugPrint('[AudioSynthService] seekSecondary: no secondary player runId=$runId');
      return false;
    }

    if (!_secondaryPrepared) {
      debugPrint('[AudioSynthService] seekSecondary: secondary not prepared, skipping seek runId=$runId');
      return false;
    }

    final targetSec = position.inMilliseconds / 1000.0;
    final state = player.state;
    final hasSource = player.source != null;
    
    debugPrint('[AudioSynthService] seekSecondary: which=secondary targetSec=$targetSec hasSource=$hasSource prepared=$_secondaryPrepared playing=${state == PlayerState.playing} state=$state runId=$runId');

    try {
      // Use timeout to prevent hanging
      await player.seek(position).timeout(
        timeout,
        onTimeout: () {
          debugPrint('[AudioSynthService] seekSecondary: TIMEOUT after ${timeout.inMilliseconds}ms runId=$runId');
          throw TimeoutException('seekSecondary timeout', timeout);
        },
      );

      // Get position after seek for logging
      final pos = await player.getCurrentPosition();
      debugPrint('[AudioSynthService] seekSecondary: done posMs=${pos?.inMilliseconds} runId=$runId');
      
      return true;
    } catch (e) {
      debugPrint('[AudioSynthService] seekSecondary: error $e runId=$runId');
      return false;
    }
  }

  Future<void> stop() async {
    await _player.stop();
    await _secondaryPlayer?.stop();
  }

  Future<void> dispose() async {
    await _player.stop();
    await _player.dispose();
    await _secondaryPlayer?.stop();
    await _secondaryPlayer?.dispose();
  }

  Future<void> _applyAudioContext() async {
    await _applyAudioContextToPlayer(_player);
  }

  Future<void> _applyAudioContextToPlayer(AudioPlayer player) async {
    await player.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
        android: AudioContextAndroid(
          contentType: AndroidContentType.music,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ),
    );
  }

  double _midiToHz(double midi) => 440.0 * pow(2.0, (midi - 69.0) / 12.0);

  double _pianoSample(double hz, double noteTime) {
    // Simple additive "piano-ish" timbre: fast attack with exponential decay.
    final attack = (noteTime / 0.02).clamp(0.0, 1.0);
    final decay = exp(-3.0 * noteTime);
    final env = attack * decay;
    final fundamental = sin(2 * pi * hz * noteTime);
    final harmonic2 = 0.6 * sin(2 * pi * hz * 2 * noteTime);
    final harmonic3 = 0.3 * sin(2 * pi * hz * 3 * noteTime);
    final harmonic4 = 0.15 * sin(2 * pi * hz * 4 * noteTime);
    return 0.45 * env * (fundamental + harmonic2 + harmonic3 + harmonic4);
  }

  Uint8List _toWav(List<double> samples) {
    final floats =
        Float64List.fromList(samples.map((s) => s.clamp(-1.0, 1.0)).toList());
    final wav = Wav([floats], sampleRate, WavFormat.pcm16bit);
    return wav.write();
  }
}
