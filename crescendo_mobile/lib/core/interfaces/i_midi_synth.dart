import 'dart:async';

/// Interface for MIDI synthesizer operations.
/// Allows testing without real MIDI hardware/plugins.
abstract class IMidiSynth {
  /// Initialize the MIDI synth.
  /// If [force] is true, reload soundfont even if already initialized.
  Future<void> init({bool force = false});

  /// Play a MIDI note.
  /// [midi] is the MIDI note number (0-127).
  /// [velocity] is the note velocity (0-127), defaults to 100.
  Future<void> playNote(int midi, {int velocity = 100});

  /// Stop a MIDI note.
  /// [midi] is the MIDI note number (0-127).
  Future<void> stopNote(int midi);

  /// Stop all currently playing notes (panic).
  Future<void> stop();
  
  /// Check if currently playing.
  bool get isPlaying;
}
