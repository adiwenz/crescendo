import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/services/review_audio_bounce_service.dart';
import '../../lib/models/reference_note.dart';
import '../../lib/models/harmonic_models.dart';
import '../../lib/utils/audio_constants.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  // Mock path provider
  // Since we can't easily mock path_provider in unit tests without a plugin registrant, 
  // we will pass a custom path to renderTickBasedWav.

  test('renderTickBasedWav generates a file', () async {
    final service = ReviewAudioBounceService();
    
    // Create a temporary directory for the test
    final tempDir =  Directory.systemTemp.createTempSync('crescendo_test_');
    final savePath = p.join(tempDir.path, 'test_tick_bounce.wav');
    
    final List<ReferenceNote> melodyNotes = [
      ReferenceNote(midi: 60, startSec: 0.0, endSec: 1.0),
      ReferenceNote(midi: 62, startSec: 1.0, endSec: 2.0),
    ];
    
    final chordEvents = [
      TickChordEvent(startTick: 0, durationTicks: 480 * 2, chord: Chord.I_Major, octaveOffset: -1), // C Major for 2 beats
      TickChordEvent(startTick: 480 * 2, durationTicks: 480 * 2, chord: Chord.V_Major, octaveOffset: -1), // V Major
    ];
    
    final modEvents = [
      TickModulationEvent(tick: 480 * 2, semitoneDelta: 2), // Modulate up 2 semitones (D Major) at beat 3
    ];
    
    final file = await service.renderTickBasedWav(
      melodyNotes: melodyNotes,
      chordEvents: chordEvents,
      modEvents: modEvents,
      initialRootMidi: 60, // C4
      durationSec: 4.0, // 2 bars
      sampleRate: 44100, // verification sample rate
      savePath: savePath,
    );
    
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(1000));
    
    // Cleanup
    tempDir.deleteSync(recursive: true);
  });
}
