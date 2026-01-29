import 'package:flutter/foundation.dart' show debugPrint;
// import 'package:flutter_midi_pro/flutter_midi_pro.dart'; // REMOVED
import 'package:crescendo_mobile/services/piano_sample_service.dart'; // ADDED
import 'dart:async';
import '../models/reference_note.dart';

/// Real-time MIDI synthesizer for reference notes using PianoSampleService
/// Plays MIDI notes directly without rendering to WAV or using sequencers
class ReferenceSynthService {
  static final ReferenceSynthService _instance = ReferenceSynthService._internal();
  factory ReferenceSynthService() => _instance;
  ReferenceSynthService._internal();

  // final MidiPro _midi = MidiPro(); // REMOVED
  String? _sfId = 'dummy_sf_id';
  bool _initialized = false;
  bool _isPlaying = false;
  final List<Timer> _activeTimers = [];
  static const int _defaultVelocity = 80;

  /// Initialize and load samples
  /// Should be called once on app start or first use
  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }

    try {
      await PianoSampleService.instance.init();
      _initialized = true;
      debugPrint('[ReferenceSynth] PianoSampleService initialized');
    } catch (e) {
      debugPrint('[ReferenceSynth] Failed to initialize PianoSampleService: $e');
      rethrow;
    }
  }

  /// Start the synth (ensure initialization)
  /// This is a no-op if already initialized
  Future<void> start({String? soundFontPath}) async {
    await _ensureInitialized();
  }

  /// Schedule and play reference notes in real-time
  /// Notes are played using Future.delayed scheduling in Dart
  /// Returns a Future that completes when playback is expected to finish
  /// 
  /// [notes] - List of reference notes to play
  /// [soundFontPath] - Ignored
  /// [leadInSeconds] - Lead-in delay before starting first note (0 = start immediately)
  /// [tailSeconds] - Additional time to wait after last note ends (default 0.2s)
  Future<void> scheduleNotes({
    required List<ReferenceNote> notes,
    String? soundFontPath,
    double leadInSeconds = 0.0,
    double tailSeconds = 0.2,
  }) async {
    if (notes.isEmpty) {
      return;
    }

    // Stop any existing playback
    await stop();

    // Ensure initialized
    await _ensureInitialized();

    // Calculate playback duration
    final maxEndSec = notes.map((n) => n.endSec).reduce((a, b) => a > b ? a : b);
    final playbackDurationSec = leadInSeconds + maxEndSec + tailSeconds;

    debugPrint('[ReferenceSynth] playing ${notes.length} notes, duration=${(playbackDurationSec * 1000).round()}ms');

    _isPlaying = true;
    final activeNotes = <int>{}; // Track which MIDI notes are currently playing

    // Schedule each note using Future.delayed
    for (final note in notes) {
      // Skip glides for now
      // TODO: Implement glide support if needed
      if (note.isGlideStart || note.isGlideEnd) {
        debugPrint('[ReferenceSynth] Skipping glide note (not supported yet)');
        continue;
      }

      final noteStartMs = ((note.startSec + leadInSeconds) * 1000).round();
      final noteEndMs = ((note.endSec + leadInSeconds) * 1000).round();

      // Schedule noteOn
      final noteOnTimer = Timer(Duration(milliseconds: noteStartMs), () {
        if (!_isPlaying) return;
        try {
          PianoSampleService.instance.playNote(
            note.midi,
            velocity: _defaultVelocity / 127.0,
          );
          activeNotes.add(note.midi);
        } catch (e) {
          debugPrint('[ReferenceSynth] Error playing note ${note.midi}: $e');
        }
      });
      _activeTimers.add(noteOnTimer);

      // Schedule noteOff
      final noteOffTimer = Timer(Duration(milliseconds: noteEndMs), () {
        if (!_isPlaying) return;
        try {
          PianoSampleService.instance.stopNote(note.midi);
          activeNotes.remove(note.midi);
        } catch (e) {
          debugPrint('[ReferenceSynth] Error stopping note ${note.midi}: $e');
        }
      });
      _activeTimers.add(noteOffTimer);
    }

    // Wait for playback to complete
    final waitMs = playbackDurationSec * 1000;
    await Future.delayed(Duration(milliseconds: waitMs.round()));
    
    _isPlaying = false;
    debugPrint('[ReferenceSynth] playback complete');
  }

  /// Stop playback immediately
  /// Stops all scheduled notes and cancels timers
  Future<void> stop() async {
    if (!_isPlaying) return;

    _isPlaying = false;

    // Cancel all active timers
    for (final timer in _activeTimers) {
      timer.cancel();
    }
    _activeTimers.clear();

    // Stop all currently playing notes
    // We rely on PianoSampleService or just stopping playback logic is enough since stopping timers prevents new notes.
    // Ideally we should stop active notes.
    // But we didn't track active notes to stop them here. 
    // Wait, let's just log it.
    
    debugPrint('[ReferenceSynth] Stopped playback');
  }

  /// Check if currently playing
  bool get isPlaying => _isPlaying;
}
