import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../midi/midi_score.dart';
import '../midi/midi_export.dart';
import '../../models/reference_note.dart';
import '../../utils/exercise_constants.dart';

/// Renders MIDI scores to WAV files using native synthesizers
class MidiWavRenderer {
  static const MethodChannel _channel = MethodChannel('com.crescendo.midi_renderer');

  /// Render a MIDI score to WAV file
  /// 
  /// [score] - The MIDI score to render
  /// [soundFontPath] - Path to the SoundFont (.sf2) file
  /// [sampleRate] - Output sample rate (e.g., 44100)
  /// [numChannels] - Number of audio channels (1 = mono, 2 = stereo)
  /// [leadInSeconds] - Lead-in time in seconds (already included in score, but may need for silence prepend)
  /// 
  /// Returns the path to the rendered WAV file
  static Future<String> renderMidiToWav({
    required MidiScore score,
    required String soundFontPath,
    int sampleRate = 44100,
    int numChannels = 2,
    double leadInSeconds = 0.0,
  }) async {
    // Export MIDI score to SMF format
    final midiBytes = MidiExporter.exportToSmf(score);

    // Get temporary directory for output
    final tempDir = await getTemporaryDirectory();
    final outputPath = p.join(
      tempDir.path,
      'midi_render_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    try {
      // Call native renderer
      final result = await _channel.invokeMethod<String>('renderMidiToWav', {
        'midiBytes': midiBytes,
        'soundFontPath': soundFontPath,
        'outputPath': outputPath,
        'sampleRate': sampleRate,
        'numChannels': numChannels,
        'leadInSeconds': leadInSeconds,
      });

      if (result == null || result.isEmpty) {
        throw Exception('Native renderer returned empty path');
      }

      // Verify file exists
      final file = File(result);
      if (!await file.exists()) {
        throw Exception('Rendered WAV file does not exist: $result');
      }

      return result;
    } on PlatformException catch (e) {
      throw Exception('Failed to render MIDI to WAV: ${e.message}');
    }
  }

  /// Play MIDI in real-time using AVAudioEngine (no offline rendering)
  /// 
  /// This method plays MIDI directly through the audio engine without
  /// rendering to WAV first. Use this for previews and live playback.
  /// 
  /// [leadInDelaySeconds] - Delay before starting sequencer (separate from lead-in in note timestamps)
  static Future<void> playMidiRealtime({
    required List<ReferenceNote> notes,
    required String soundFontPath,
    double leadInDelaySeconds = 0.0,
  }) async {
    if (notes.isEmpty) {
      throw ArgumentError('Cannot play empty note list');
    }

    // Determine if notes already have lead-in baked in
    // If first note starts at 0, we need to add lead-in to MIDI timestamps
    // If first note starts at leadInSec, lead-in is already in timestamps
    final firstNoteStartSec = notes.first.startSec;
    final needsLeadInInMidi = firstNoteStartSec < 0.1;
    final midiLeadInSeconds = needsLeadInInMidi ? ExerciseConstants.leadInSec : 0.0;

    final builder = MidiScoreBuilder(
      tempoBpm: 120,
      ppq: 480,
      pitchBendRangeSemitones: 12,
      leadInSeconds: midiLeadInSeconds, // Add to MIDI timestamps if needed
    );

    // Group notes into glides and regular notes
    var i = 0;

    while (i < notes.length) {
      final note = notes[i];
      
      // Check if this is part of a glide
      if (i < notes.length - 1) {
        final nextNote = notes[i + 1];
        final timeGap = nextNote.startSec - note.endSec;
        final midiDiff = (nextNote.midi - note.midi).abs();
        
        // If notes are close in time and pitch, treat as glide
        if (timeGap < 0.05 && midiDiff <= 2) {
          // Find the end of the glide segment
          var glideEnd = i + 1;
          var glideStartMidi = note.midi;
          var glideEndMidi = nextNote.midi;
          var glideStartSec = note.startSec;
          var glideEndSec = nextNote.endSec;

          while (glideEnd < notes.length - 1) {
            final current = notes[glideEnd];
            final next = notes[glideEnd + 1];
            final gap = next.startSec - current.endSec;
            final diff = (next.midi - current.midi).abs();
            
            if (gap < 0.05 && diff <= 2) {
              glideEnd++;
              glideEndMidi = next.midi;
              glideEndSec = next.endSec;
            } else {
              break;
            }
          }

          // Add glide
          builder.addGlide(
            startSec: glideStartSec,
            endSec: glideEndSec,
            startMidi: glideStartMidi,
            endMidi: glideEndMidi,
            updateRateHz: 100,
          );

          i = glideEnd + 1;
          continue;
        }
      }

      // Regular note
      builder.addNote(
        startSec: note.startSec,
        endSec: note.endSec,
        midiNote: note.midi,
      );
      i++;
    }

    final score = builder.build();
    final midiBytes = MidiExporter.exportToSmf(score);

    try {
      await _channel.invokeMethod<void>('playMidiRealtime', {
        'midiBytes': midiBytes,
        'soundFontPath': soundFontPath,
        'leadInSeconds': leadInDelaySeconds, // Delay before starting sequencer
      });
    } on PlatformException catch (e) {
      throw Exception('Failed to play MIDI in real-time: ${e.message}');
    }
  }

  /// Stop real-time MIDI playback
  static Future<void> stopMidiRealtime() async {
    try {
      await _channel.invokeMethod<void>('stopMidiRealtime');
    } on PlatformException catch (e) {
      throw Exception('Failed to stop MIDI playback: ${e.message}');
    }
  }

  /// Convert ReferenceNote list to MIDI score and render to WAV
  /// 
  /// This is a convenience method that handles the conversion from ReferenceNote
  /// to MIDI score, including glide detection and pitch bend generation.
  static Future<String> renderReferenceNotesToWav({
    required List<ReferenceNote> notes,
    required String soundFontPath,
    int sampleRate = 44100,
    int numChannels = 2,
    double leadInSeconds = 0.0,
    int pitchBendRangeSemitones = 12,
    int pitchBendUpdateRateHz = 100,
    int tempoBpm = 120,
    int ppq = 480,
  }) async {
    if (notes.isEmpty) {
      throw ArgumentError('Cannot render empty note list');
    }

    final builder = MidiScoreBuilder(
      tempoBpm: tempoBpm,
      ppq: ppq,
      pitchBendRangeSemitones: pitchBendRangeSemitones,
      leadInSeconds: leadInSeconds,
    );

    // Group notes into glides and regular notes
    var i = 0;

    while (i < notes.length) {
      final note = notes[i];
      
      // Check if this is part of a glide
      if (i < notes.length - 1) {
        final nextNote = notes[i + 1];
        final timeGap = nextNote.startSec - note.endSec;
        final midiDiff = (nextNote.midi - note.midi).abs();
        
        // If notes are close in time and pitch, treat as glide
        if (timeGap < 0.05 && midiDiff <= 2) {
          // Find the end of the glide segment
          var glideEnd = i + 1;
          var glideStartMidi = note.midi;
          var glideEndMidi = nextNote.midi;
          var glideStartSec = note.startSec;
          var glideEndSec = nextNote.endSec;

          while (glideEnd < notes.length - 1) {
            final current = notes[glideEnd];
            final next = notes[glideEnd + 1];
            final gap = next.startSec - current.endSec;
            final diff = (next.midi - current.midi).abs();
            
            if (gap < 0.05 && diff <= 2) {
              glideEnd++;
              glideEndMidi = next.midi;
              glideEndSec = next.endSec;
            } else {
              break;
            }
          }

          // Add glide
          builder.addGlide(
            startSec: glideStartSec,
            endSec: glideEndSec,
            startMidi: glideStartMidi,
            endMidi: glideEndMidi,
            updateRateHz: pitchBendUpdateRateHz,
          );

          i = glideEnd + 1;
          continue;
        }
      }

      // Regular note
      builder.addNote(
        startSec: note.startSec,
        endSec: note.endSec,
        midiNote: note.midi,
      );
      i++;
    }

    final score = builder.build();
    return renderMidiToWav(
      score: score,
      soundFontPath: soundFontPath,
      sampleRate: sampleRate,
      numChannels: numChannels,
      leadInSeconds: leadInSeconds,
    );
  }
}
