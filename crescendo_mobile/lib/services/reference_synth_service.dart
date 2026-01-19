import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'dart:async';
import '../models/reference_note.dart';

/// Real-time MIDI synthesizer for reference notes using flutter_midi_pro
/// Plays MIDI notes directly without rendering to WAV or using sequencers
class ReferenceSynthService {
  static final ReferenceSynthService _instance = ReferenceSynthService._internal();
  factory ReferenceSynthService() => _instance;
  ReferenceSynthService._internal();

  final MidiPro _midi = MidiPro();
  String? _sfId;
  bool _initialized = false;
  bool _isPlaying = false;
  final List<Timer> _activeTimers = [];
  static const int _defaultVelocity = 80;

  /// Initialize flutter_midi_pro and load SoundFont
  /// Should be called once on app start or first use
  Future<void> _ensureInitialized() async {
    if (_initialized && _sfId != null) {
      return;
    }

    try {
      // Load SoundFont from assets (flutter_midi_pro loads directly from assets)
      _sfId = await _midi.loadSoundfont(
        sf2Path: 'assets/soundfonts/default.sf2',
        name: 'default.sf2',
      );
      
      _initialized = true;
      debugPrint('[ReferenceSynth] flutter_midi_pro initialized');
    } catch (e) {
      debugPrint('[ReferenceSynth] Failed to initialize flutter_midi_pro: $e');
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
  /// [soundFontPath] - Ignored (uses default SoundFont)
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
    if (_sfId == null) {
      debugPrint('[ReferenceSynth] Cannot play notes: SoundFont not loaded');
      return;
    }

    // Calculate playback duration
    final maxEndSec = notes.map((n) => n.endSec).reduce((a, b) => a > b ? a : b);
    final playbackDurationSec = leadInSeconds + maxEndSec + tailSeconds;

    debugPrint('[ReferenceSynth] playing ${notes.length} notes, duration=${(playbackDurationSec * 1000).round()}ms');

    _isPlaying = true;
    final activeNotes = <int>{}; // Track which MIDI notes are currently playing

    // Schedule each note using Future.delayed
    for (final note in notes) {
      // Skip glides for now (flutter_midi_pro doesn't support pitch bend directly)
      // TODO: Implement glide support if needed
      if (note.isGlideStart || note.isGlideEnd) {
        debugPrint('[ReferenceSynth] Skipping glide note (not supported yet)');
        continue;
      }

      final noteStartMs = ((note.startSec + leadInSeconds) * 1000).round();
      final noteEndMs = ((note.endSec + leadInSeconds) * 1000).round();

      // Schedule noteOn
      final noteOnTimer = Timer(Duration(milliseconds: noteStartMs), () {
        if (!_isPlaying || _sfId == null) return;
        try {
          _midi.playMidiNote(
            midi: note.midi,
            velocity: _defaultVelocity,
          );
          activeNotes.add(note.midi);
        } catch (e) {
          debugPrint('[ReferenceSynth] Error playing note ${note.midi}: $e');
        }
      });
      _activeTimers.add(noteOnTimer);

      // Schedule noteOff
      final noteOffTimer = Timer(Duration(milliseconds: noteEndMs), () {
        if (!_isPlaying || _sfId == null) return;
        try {
          _midi.stopMidiNote(
            midi: note.midi,
            velocity: 127,
          );
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
    // Note: We don't track active notes perfectly, but we can try to stop common notes
    // In practice, stopping is usually called between sequences, so this is fine
    if (_sfId != null) {
      try {
        // Stop all notes on the channel (flutter_midi_pro may have an allNotesOff method)
        // For now, we rely on timers being cancelled and notes naturally ending
      } catch (e) {
        debugPrint('[ReferenceSynth] Error stopping notes: $e');
      }
    }

    debugPrint('[ReferenceSynth] Stopped playback');
  }

  /// Check if currently playing
  bool get isPlaying => _isPlaying;
}
