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

  /// Seek the primary player to a specific position
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// Seek the secondary player to a specific position
  Future<void> seekSecondary(Duration position) async {
    await _secondaryPlayer?.seek(position);
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
