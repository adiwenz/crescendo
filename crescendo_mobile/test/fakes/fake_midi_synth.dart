import 'dart:async';
import 'package:crescendo_mobile/core/interfaces/i_midi_synth.dart';

/// Fake MIDI synth for testing.
/// Tracks all playNote/stopNote calls for verification.
class FakeMidiSynth implements IMidiSynth {
  bool _initialized = false;
  bool _isPlaying = false;
  final List<MidiEvent> events = [];
  final Set<int> activeNotes = {};
  int initCallCount = 0;
  int forceInitCallCount = 0;

  @override
  Future<void> init({bool force = false}) async {
    initCallCount++;
    if (force) {
      forceInitCallCount++;
      _initialized = false; // Reset state on force
    }
    _initialized = true;
  }

  @override
  Future<void> playNote(int midi, {int velocity = 100}) async {
    events.add(MidiEvent(MidiEventType.noteOn, midi, velocity));
    activeNotes.add(midi);
    _isPlaying = true;
  }

  @override
  Future<void> stopNote(int midi) async {
    events.add(MidiEvent(MidiEventType.noteOff, midi, 0));
    activeNotes.remove(midi);
  }

  @override
  Future<void> stop() async {
    events.add(MidiEvent(MidiEventType.stop, 0, 0));
    activeNotes.clear();
    _isPlaying = false;
  }

  @override
  bool get isPlaying => _isPlaying;

  /// Get all played notes (noteOn events).
  List<int> getPlayedNotes() {
    return events
        .where((e) => e.type == MidiEventType.noteOn)
        .map((e) => e.midi)
        .toList();
  }

  /// Get all stopped notes (noteOff events).
  List<int> getStoppedNotes() {
    return events
        .where((e) => e.type == MidiEventType.noteOff)
        .map((e) => e.midi)
        .toList();
  }

  /// Clear all tracked events (for test cleanup).
  void clear() {
    events.clear();
    activeNotes.clear();
    _isPlaying = false;
    initCallCount = 0;
    forceInitCallCount = 0;
  }

  bool get initialized => _initialized;
}

enum MidiEventType { noteOn, noteOff, stop }

class MidiEvent {
  final MidiEventType type;
  final int midi;
  final int velocity;

  MidiEvent(this.type, this.midi, this.velocity);

  @override
  String toString() => 'MidiEvent($type, midi=$midi, velocity=$velocity)';
}
