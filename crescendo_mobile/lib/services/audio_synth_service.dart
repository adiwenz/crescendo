import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/reference_note.dart';

class AudioSynthService {
  static const double tailSeconds = 1.0;
  final int sampleRate;
  final AudioPlayer _player;

  AudioSynthService({this.sampleRate = 44100}) : _player = AudioPlayer();

  Future<String> renderReferenceNotes(List<ReferenceNote> notes) async {
    final samples = <double>[];
    double cursor = 0;
    ReferenceNote? lastNote;
    double lastNoteDur = 0.0;
    for (final n in notes) {
      if (n.startSec > cursor) {
        final gapFrames = ((n.startSec - cursor) * sampleRate).toInt();
        samples.addAll(List.filled(gapFrames, 0.0));
        cursor = n.startSec;
      }
      final dur = max(0.01, n.endSec - n.startSec);
      final frames = (dur * sampleRate).toInt();
      final hz = _midiToHz(n.midi.toDouble());
      for (var f = 0; f < frames; f++) {
        samples.add(_pianoSample(hz, f / sampleRate));
      }
      cursor = n.endSec;
      lastNote = n;
      lastNoteDur = dur;
    }
    if (lastNote != null) {
      final hz = _midiToHz(lastNote.midi.toDouble());
      final releaseFrames = (tailSeconds * sampleRate).toInt();
      for (var f = 0; f < releaseFrames; f++) {
        final t = lastNoteDur + f / sampleRate;
        final fade = 1.0 - (f / releaseFrames);
        samples.add(_pianoSample(hz, t) * fade);
      }
    }
    if (samples.isEmpty) {
      final frames = (0.1 * sampleRate).toInt();
      samples.addAll(List.filled(frames, 0.0));
    }

    final bytes = _toWav(samples);
    final dir = await getTemporaryDirectory();
    final path = p.join(
        dir.path, 'pitch_highway_${DateTime.now().millisecondsSinceEpoch}.wav');
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> playFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return;
    final size = await file.length();
    if (size <= 0) return;
    await _player.stop();
    await _player.setVolume(1.0);
    try {
      await _player.play(DeviceFileSource(path, mimeType: 'audio/wav'));
    } on PlatformException {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;
      await _player.play(BytesSource(bytes, mimeType: 'audio/wav'));
    } on AudioPlayerException {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;
      await _player.play(BytesSource(bytes, mimeType: 'audio/wav'));
    }
  }

  Stream<void> get onComplete => _player.onPlayerComplete;

  Future<void> stop() => _player.stop();

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
    final bytes = ByteData(44 + samples.length * 2);
    final dataSize = samples.length * 2;
    const channels = 1;
    bytes.setUint32(0, 0x52494646, Endian.big); // RIFF
    bytes.setUint32(4, dataSize + 36, Endian.little);
    bytes.setUint32(8, 0x57415645, Endian.big); // WAVE
    bytes.setUint32(12, 0x666d7420, Endian.big); // fmt
    bytes.setUint32(16, 16, Endian.little); // pcm chunk
    bytes.setUint16(20, 1, Endian.little); // audio format PCM
    bytes.setUint16(22, channels, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * channels * 2, Endian.little);
    bytes.setUint16(32, channels * 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    bytes.setUint32(36, 0x64617461, Endian.big); // data
    bytes.setUint32(40, dataSize, Endian.little);
    var offset = 44;
    for (final s in samples) {
      final v = (s.clamp(-1.0, 1.0) * 32767).toInt();
      bytes.setInt16(offset, v, Endian.little);
      offset += 2;
    }
    return bytes.buffer.asUint8List();
  }
}
