import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import '../models/reference_note.dart';

/// Real-time MIDI synthesizer for reference audio playback using flutter_midi_pro
/// Plays MIDI notes directly without rendering to WAV files
class ReferenceMidiSynth {
  static final ReferenceMidiSynth _instance = ReferenceMidiSynth._internal();
  factory ReferenceMidiSynth() => _instance;
  ReferenceMidiSynth._internal();

  final MidiPro _midi = MidiPro();
  String? _sfId;
  bool _initialized = false;
  bool _isPlaying = false;
  final List<Timer> _activeTimers = [];
  int? _currentRunId;
  static const int _defaultVelocity = 100;

  /// Initialize flutter_midi_pro and load SoundFont (idempotent)
  /// Should be called once at app startup or once per screen lifetime
  Future<void> init() async {
    if (_initialized && _sfId != null) {
      return;
    }

    try {
      debugPrint('[ReferenceMidiSynth] Loading SoundFont...');
      _sfId = await _midi.loadSoundfont(
        sf2Path: 'assets/soundfonts/default.sf2',
        name: 'default.sf2',
      );
      _initialized = true;
      debugPrint('[ReferenceMidiSynth] SoundFont loaded successfully, ID: $_sfId');
    } catch (e) {
      debugPrint('[ReferenceMidiSynth] Failed to initialize: $e');
      rethrow;
    }
  }

  /// Play a sequence of reference notes using Timer scheduling
  /// 
  /// [notes] - List of reference notes to play
  /// [leadInSec] - Lead-in delay before starting first note (0 = start immediately)
  /// [runId] - Run ID to guard against stale callbacks (must match current runId)
  /// [startEpochMs] - Timeline anchor epoch in milliseconds (for logging/debugging)
  /// 
  /// Notes are scheduled relative to the current time, using the startEpochMs
  /// as a reference point for logging purposes only. Actual playback timing
  /// is based on Timer scheduling from method call time.
  Future<void> playSequence({
    required List<ReferenceNote> notes,
    double leadInSec = 0.0,
    required int runId,
    int? startEpochMs,
  }) async {
    if (notes.isEmpty) {
      debugPrint('[ReferenceMidiSynth] No notes to play');
      return;
    }

    // Stop any existing playback
    await stop();

    // Ensure initialized
    await init();
    if (_sfId == null) {
      debugPrint('[ReferenceMidiSynth] Cannot play notes: SoundFont not loaded');
      return;
    }

    // Set current run ID
    _currentRunId = runId;
    _isPlaying = true;

    // Calculate note timing
    final minStartSec = notes.map((n) => n.startSec).reduce((a, b) => a < b ? a : b);
    final maxEndSec = notes.map((n) => n.endSec).reduce((a, b) => a > b ? a : b);
    final firstNoteStartSec = minStartSec + leadInSec;
    final lastNoteEndSec = maxEndSec + leadInSec;

    // Log sequence start (one line with key info)
    debugPrint(
        '[ReferenceMidiSynth] Playing sequence: ${notes.length} notes, '
        'firstNote=${notes.first.midi}@${firstNoteStartSec.toStringAsFixed(2)}s, '
        'lastNote=${notes.last.midi}@${lastNoteEndSec.toStringAsFixed(2)}s, '
        'runId=$runId');

    // Track when first note actually fires (for debugging)
    bool firstNoteFired = false;
    final sequenceStartTime = DateTime.now();

    // Schedule each note using Timer
    for (final note in notes) {
      // Skip glides for now (flutter_midi_pro doesn't support pitch bend directly)
      if (note.isGlideStart || note.isGlideEnd) {
        debugPrint('[ReferenceMidiSynth] Skipping glide note (not supported yet)');
        continue;
      }

      // Calculate absolute times relative to method call time
      final noteStartMs = ((note.startSec + leadInSec) * 1000).round();
      final noteEndMs = ((note.endSec + leadInSec) * 1000).round();

      // Schedule noteOn
      final noteOnTimer = Timer(Duration(milliseconds: noteStartMs), () {
        // Guard against stale callbacks
        if (_currentRunId != runId || !_isPlaying || _sfId == null) {
          if (_currentRunId != runId) {
            debugPrint('[ReferenceMidiSynth] Ignored stale noteOn: runId=$runId, current=$_currentRunId');
          }
          return;
        }

        try {
          _midi.playMidiNote(midi: note.midi, velocity: _defaultVelocity);
          
          // Log first note firing (one line)
          if (!firstNoteFired) {
            firstNoteFired = true;
            final elapsedFromStart = DateTime.now().difference(sequenceStartTime).inMilliseconds;
            final elapsedFromEpoch = startEpochMs != null
                ? DateTime.now().millisecondsSinceEpoch - startEpochMs
                : null;
            debugPrint(
                '[ReferenceMidiSynth] First note ON: MIDI=${note.midi} '
                'at ${noteStartMs}ms (${elapsedFromStart}ms after schedule, '
                '${elapsedFromEpoch != null ? "${elapsedFromEpoch}ms after epoch" : "epoch=N/A"})');
          }
        } catch (e) {
          debugPrint('[ReferenceMidiSynth] Error playing note ${note.midi}: $e');
        }
      });
      _activeTimers.add(noteOnTimer);

      // Schedule noteOff
      final noteOffTimer = Timer(Duration(milliseconds: noteEndMs), () {
        // Guard against stale callbacks
        if (_currentRunId != runId || !_isPlaying || _sfId == null) {
          return;
        }

        try {
          _midi.stopMidiNote(midi: note.midi, velocity: 127);
        } catch (e) {
          debugPrint('[ReferenceMidiSynth] Error stopping note ${note.midi}: $e');
        }
      });
      _activeTimers.add(noteOffTimer);
    }

    // Log sequence scheduled
    debugPrint('[ReferenceMidiSynth] Sequence scheduled: ${notes.length} notes, runId=$runId');
  }

  /// Stop playback immediately
  /// Cancels all scheduled timers and stops all active notes
  Future<void> stop() async {
    if (!_isPlaying) return;

    _isPlaying = false;
    final timerCount = _activeTimers.length;
    _currentRunId = null;

    // Cancel all active timers
    for (final timer in _activeTimers) {
      timer.cancel();
    }
    _activeTimers.clear();

    debugPrint('[ReferenceMidiSynth] Stopped playback (cancelled $timerCount timers)');
  }

  /// Check if currently playing
  bool get isPlaying => _isPlaying;

  /// Get current run ID (for debugging)
  int? get currentRunId => _currentRunId;
}
