import 'package:flutter/foundation.dart' show debugPrint;
import 'models/reference_note.dart';
import 'services/pitch_service.dart';
import 'services/reference_synth_service.dart';

/// Simple MIDI scale player for testing/quick playback
class MidiScalePlayer {
  static final ReferenceSynthService _synth = ReferenceSynthService();

  /// Play a single MIDI note (C4)
  static Future<void> playSingleNote() async {
    final notes = [
      ReferenceNote(startSec: 0.0, endSec: 0.5, midi: 60), // C4
    ];

    // Use pauseForMidiPlaybackAndPlay to ensure mic doesn't restart during playback
    await PitchService.instance.pauseForMidiPlaybackAndPlay(() async {
      await _synth.start();
      final maxEndSec = notes.map((n) => n.endSec).reduce((a, b) => a > b ? a : b);
      final waitMs = ((maxEndSec + 0.2) * 1000).round();
      debugPrint('[MidiScalePlayer] waiting ${waitMs}ms for playback');
      await _synth.scheduleNotes(notes: notes, leadInSeconds: 0.0, tailSeconds: 0.2);
    });
  }

  /// Play a 5-note ascending scale (C4, D4, E4, F4, G4)
  static Future<void> playFiveNoteScale() async {
    final notes = [
      ReferenceNote(startSec: 0.0, endSec: 0.5, midi: 60), // C4
      ReferenceNote(startSec: 0.6, endSec: 1.1, midi: 62), // D4
      ReferenceNote(startSec: 1.2, endSec: 1.7, midi: 64), // E4
      ReferenceNote(startSec: 1.8, endSec: 2.3, midi: 65), // F4
      ReferenceNote(startSec: 2.4, endSec: 2.9, midi: 67), // G4
    ];

    // Use pauseForMidiPlaybackAndPlay to ensure mic doesn't restart during playback
    await PitchService.instance.pauseForMidiPlaybackAndPlay(() async {
      await _synth.start();
      final maxEndSec = notes.map((n) => n.endSec).reduce((a, b) => a > b ? a : b);
      final waitMs = ((maxEndSec + 0.2) * 1000).round();
      debugPrint('[MidiScalePlayer] waiting ${waitMs}ms for playback');
      await _synth.scheduleNotes(notes: notes, leadInSeconds: 0.0, tailSeconds: 0.2);
    });
  }
}
