import 'dart:async';
import '../interfaces/i_midi_synth.dart';
import '../../audio/reference_midi_synth.dart';

/// Real implementation of IMidiSynth wrapping ReferenceMidiSynth.
class RealMidiSynth implements IMidiSynth {
  final ReferenceMidiSynth _synth = ReferenceMidiSynth.instance;

  @override
  Future<void> init({bool force = false}) async {
    await _synth.init(force: force);
  }

  @override
  Future<void> playNote(int midi, {int velocity = 100}) async {
    await _synth.playNote(midi, velocity: velocity);
  }

  @override
  Future<void> stopNote(int midi) async {
    await _synth.stopNote(midi);
  }

  @override
  Future<void> stop() async {
    await _synth.stop();
  }

  @override
  bool get isPlaying => _synth.isPlaying;
}
