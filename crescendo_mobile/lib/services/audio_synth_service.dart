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
import '../utils/audio_constants.dart';
import 'chirp_marker.dart';

class AudioSynthService {
  static const double tailSeconds = 1.0;
  final int sampleRate;
  final AudioPlayer _player;
  final AudioPlayer?
      _secondaryPlayer; // For mixing reference notes with recorded audio
  String?
      _secondaryPreparedPath; // Track which file secondary player is prepared for
  bool _secondaryPrepared = false;

  AudioSynthService({this.sampleRate = AudioConstants.audioSampleRate, bool enableMixing = false})
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
    // Inject Ultrasonic Chirp at start
    final chirpFloats = ChirpMarker.generateChirpWaveform(sampleRate: sampleRate);
    final chirpDoubles = chirpFloats.map((e) => e.toDouble()).toList();
    samples.addAll(chirpDoubles);
    
    // Add 20ms silence buffer after chirp
    final silenceSamples = (0.02 * sampleRate).toInt();
    samples.addAll(List.filled(silenceSamples, 0.0));
    
    // [REF_GEN] LOGS
    final chirpLenSamples = chirpDoubles.length;
    final chirpLenMs = (chirpLenSamples / sampleRate) * 1000;
    final musicStartSample = samples.length;
    final musicStartMs = (musicStartSample / sampleRate) * 1000;
    
    debugPrint('[REF_GEN] sr=$sampleRate');
    debugPrint('[REF_GEN] chirpLenSamples=$chirpLenSamples chirpLenMs=${chirpLenMs.toStringAsFixed(1)}');
    debugPrint('[REF_GEN] musicStartSample=$musicStartSample musicStartMs=${musicStartMs.toStringAsFixed(1)}');
    
    // Offset cursor so notes start AFTER chirp + silence
    // We want the visual notes to align with the audio notes.
    // If we shift audio by inserting chirp, we shift visual alignment!
    // BUT the prompt says: "Reference audio includes a short ultrasonic chirp at a known sample index".
    // And "Pitch frame timestamps MUST be corrected... correctedTime = rawFrameTime - audioSyncInfo.timeOffsetSec".
    // If we insert the chirp, the "Music" starts later.
    // The "ReferenceNote" startSecs are 0-based.
    // If we insert 100ms at the start, the music starts at 0.1s.
    // So visual notes (which expect music at 0) will be EARLY by 0.1s unless we offset visuals OR subtract this offset.
    // However, the *Ultrasonic Sync* computes offset between Ref Chirp and Rec Chirp.
    // If Ref Chirp is at 0, and we align Rec to Ref, then Rec is aligned to Ref's time base.
    // If Ref has chirp at 0 and music at 0.1, then aligned recording will have sampled music at 0.1.
    // We need to think about this:
    // User: "Play reference audio normally from t=0".
    // If we inject chirp, "t=0" contains chirp. Music starts at t=0.1.
    // We should probably start the notes a bit later in the generated audio?
    // OR we shift the notes in the audio generation?
    // `startSec` in `noteData` is what the visual uses.
    // I should shift the audio notes by `chirpDuration + silence`.
    // Let's define `startOffset`.
    
    final startOffset = chirpDoubles.length / sampleRate + 0.02;
    double cursor = startOffset; // Start placing notes from here
    Map<String, dynamic>? lastNote;
    double lastNoteDur = 0.0;

    for (final n in noteData) {
      final startSec = n['startSec'] as double;
      final endSec = n['endSec'] as double;
      final midi = (n['midi'] as num).toDouble();

      // Ensure we don't go backwards if note starts very early (e.g. 0.0)
      // Though for Pitch Highway we have lead-in so startSec is ~2.0.
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
    
    debugPrint('[REF_GEN] totalSamples=${samples.length}');

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
    if (size <= 0) return;
    
    // Log WAV header info for debugging speed mismatch
    await _logWavDetails(path);
    
    await _player.stop();
    await _applyAudioContext();
    await _player.setVolume(1.0);

    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;
      await _player.setSourceBytes(bytes, mimeType: 'audio/wav');
      await _player.resume();
    } on PlatformException {
      await _player.play(DeviceFileSource(path, mimeType: 'audio/wav'));
    } on AudioPlayerException {
      await _player.play(DeviceFileSource(path, mimeType: 'audio/wav'));
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

  AudioPlayer get player => _player;

  /// Seek the primary player to a specific position (with timeout protection)
  Future<bool> seek(Duration position,
      {int? runId, Duration timeout = const Duration(seconds: 2)}) async {
    final state = _player.state;
    final hasSource = _player.source != null;
    final targetSec = position.inMilliseconds / 1000.0;

    debugPrint(
        '[AudioSynthService] seek: which=primary targetSec=$targetSec hasSource=$hasSource playing=${state == PlayerState.playing} state=$state runId=$runId');

    try {
      await _player.seek(position).timeout(
        timeout,
        onTimeout: () {
          debugPrint(
              '[AudioSynthService] seek: TIMEOUT after ${timeout.inMilliseconds}ms runId=$runId');
          throw TimeoutException('seek timeout', timeout);
        },
      );

      // Get position after seek for logging
      final pos = await _player.getCurrentPosition();
      debugPrint(
          '[AudioSynthService] seek: done posMs=${pos?.inMilliseconds} runId=$runId');

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
      debugPrint(
          '[AudioSynthService] ensureSecondaryPrepared: no secondary player');
      return false;
    }

    // If already prepared for this file, skip
    if (_secondaryPrepared && _secondaryPreparedPath == path) {
      debugPrint(
          '[AudioSynthService] ensureSecondaryPrepared: already prepared for $path runId=$runId');
      return true;
    }

    try {
      debugPrint(
          '[AudioSynthService] ensureSecondaryPrepared: preparing $path runId=$runId');

      // Stop and reset
      await player.stop();
      _secondaryPrepared = false;
      _secondaryPreparedPath = null;

      // Set source
      final file = File(path);
      if (!await file.exists()) {
        debugPrint(
            '[AudioSynthService] ensureSecondaryPrepared: file not found $path runId=$runId');
        return false;
      }

      await player.setVolume(1.0);
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          debugPrint(
              '[AudioSynthService] ensureSecondaryPrepared: empty file $path runId=$runId');
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
      debugPrint(
          '[AudioSynthService] ensureSecondaryPrepared: ready durationMs=${duration?.inMilliseconds} runId=$runId');

      return true;
    } catch (e) {
      debugPrint(
          '[AudioSynthService] ensureSecondaryPrepared: error $e runId=$runId');
      _secondaryPrepared = false;
      _secondaryPreparedPath = null;
      return false;
    }
  }

  /// Seek the secondary player with timeout (non-blocking)
  Future<bool> seekSecondary(Duration position,
      {int? runId, Duration timeout = const Duration(seconds: 2)}) async {
    final player = _secondaryPlayer;
    if (player == null) {
      debugPrint(
          '[AudioSynthService] seekSecondary: no secondary player runId=$runId');
      return false;
    }

    if (!_secondaryPrepared) {
      debugPrint(
          '[AudioSynthService] seekSecondary: secondary not prepared, skipping seek runId=$runId');
      return false;
    }

    final targetSec = position.inMilliseconds / 1000.0;
    final state = player.state;
    final hasSource = player.source != null;

    debugPrint(
        '[AudioSynthService] seekSecondary: which=secondary targetSec=$targetSec hasSource=$hasSource prepared=$_secondaryPrepared playing=${state == PlayerState.playing} state=$state runId=$runId');

    try {
      // Use timeout to prevent hanging
      await player.seek(position).timeout(
        timeout,
        onTimeout: () {
          debugPrint(
              '[AudioSynthService] seekSecondary: TIMEOUT after ${timeout.inMilliseconds}ms runId=$runId');
          throw TimeoutException('seekSecondary timeout', timeout);
        },
      );

      // Get position after seek for logging
      final pos = await player.getCurrentPosition();
      debugPrint(
          '[AudioSynthService] seekSecondary: done posMs=${pos?.inMilliseconds} runId=$runId');

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

  Future<void> pause() async {
    await _player.pause();
    await _secondaryPlayer?.pause();
  }

  Future<void> resume() async {
    await _player.resume();
    await _secondaryPlayer?.resume();
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
          category: AVAudioSessionCategory.playAndRecord,
          options: {
            AVAudioSessionOptions.mixWithOthers,
            AVAudioSessionOptions.defaultToSpeaker,
            AVAudioSessionOptions.allowBluetooth,
          },
        ),
        android: AudioContextAndroid(
          isSpeakerphoneOn: true, // Output to speaker during recording
          stayAwake: false,
          contentType: AndroidContentType.speech, // Match AudioSession
          usageType: AndroidUsageType.voiceCommunication, // KEY: match AudioSession usage
          audioFocus: AndroidAudioFocus.gainTransientMayDuck, // KEY: duckable, not exclusive
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
  Future<void> _logWavDetails(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return;
      
      final size = await file.length();
      final openFile = await file.open();
      final headerBytes = await openFile.read(44);
      await openFile.close();
      
      if (headerBytes.length < 44) {
        debugPrint('[AudioSynthLog] $path: Too small for WAV header ($size bytes)');
        return;
      }
      
      // Parse basic WAV header
      final riff = String.fromCharCodes(headerBytes.sublist(0, 4));
      final wave = String.fromCharCodes(headerBytes.sublist(8, 12));
      final fmt = String.fromCharCodes(headerBytes.sublist(12, 16).map((e) => e == 0 ? 32 : e)); // Handle nulls if any, though fmt is usually 'fmt '
      
      if (riff != 'RIFF' || wave != 'WAVE') {
         debugPrint('[AudioSynthLog] $path: Not a valid WAV (RIFF=$riff, WAVE=$wave)');
         return;
      }
      
      // fmt chunk
      // offsets:
      // 22: NumChannels (2 bytes)
      // 24: SampleRate (4 bytes)
      // 28: ByteRate (4 bytes)
      // 32: BlockAlign (2 bytes)
      // 34: BitsPerSample (2 bytes)
      
      final channels = headerBytes[22] | (headerBytes[23] << 8);
      final sampleRate = headerBytes[24] | (headerBytes[25] << 8) | (headerBytes[26] << 16) | (headerBytes[27] << 24);
      final bits = headerBytes[34] | (headerBytes[35] << 8);
      
      // Compute duration from size (approximate if extra chunks exist, but good enough)
      // Duration = (TotalBytes - 44) / (SampleRate * Channels * Bits/8)
      final bytesPerSec = sampleRate * channels * (bits / 8);
      final durationSec = (size - 44) / bytesPerSec;
      
      // Generate partial hash (first 64 bytes + size) to fingerprint
      // We read 44, let's just use what we have + size
      final quickHash = '${path.hashCode ^ size}';

      debugPrint('[AudioSynthLog] PLAYING: $path');
      debugPrint('[AudioSynthLog]   Size: $size bytes');
      debugPrint('[AudioSynthLog]   Format: ${sampleRate}Hz, ${channels}ch, ${bits}bit');
      debugPrint('[AudioSynthLog]   Duration: ${durationSec.toStringAsFixed(3)}s');
      debugPrint('[AudioSynthLog]   Hash: $quickHash');
      
    } catch (e) {
      debugPrint('[AudioSynthLog] Error reading header for $path: $e');
    }
  }
}
