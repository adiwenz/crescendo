import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import '../models/reference_note.dart';
import 'midi_playback_config.dart';

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
  final Set<int> _activeNotes = {}; // Track notes that are currently playing (noteOn sent, noteOff not yet sent)
  int? _currentRunId;
  static const int _defaultVelocity = 100;

  /// Initialize flutter_midi_pro and load SoundFont (idempotent)
  /// Should be called once at app startup or once per screen lifetime
  /// [config] - MIDI playback configuration (if provided, ensures correct SoundFont is loaded)
  Future<void> init({MidiPlaybackConfig? config}) async {
    final effectiveConfig = config ?? MidiPlaybackConfig.exercise();
    
    // If already initialized with the same SoundFont, skip
    if (_initialized && _sfId != null) {
      // TODO: Check if SoundFont matches config (flutter_midi_pro may not support this)
      // For now, assume if initialized, it's correct
      return;
    }

    try {
      debugPrint('[ReferenceMidiSynth] Loading SoundFont: ${effectiveConfig.soundFontName}...');
      _sfId = await _midi.loadSoundfont(
        sf2Path: effectiveConfig.soundFontAssetPath,
        name: effectiveConfig.soundFontName,
      );
      _initialized = true;
      debugPrint('[ReferenceMidiSynth] SoundFont loaded successfully, ID: $_sfId');
      
      // TODO: Set program/bank/channel if flutter_midi_pro supports it
      // Currently flutter_midi_pro may not expose these APIs, so we log what we would set
      if (effectiveConfig.program != 0 || effectiveConfig.bankMSB != 0 || effectiveConfig.bankLSB != 0) {
        debugPrint('[ReferenceMidiSynth] Note: program=${effectiveConfig.program} bankMSB=${effectiveConfig.bankMSB} bankLSB=${effectiveConfig.bankLSB} requested but may not be supported by flutter_midi_pro');
      }
      
      // TODO: Set pitch bend if enabled and supported
      if (effectiveConfig.enablePitchBend && effectiveConfig.initialPitchBend != 8192) {
        debugPrint('[ReferenceMidiSynth] Note: pitchBend=${effectiveConfig.initialPitchBend} requested but may not be supported by flutter_midi_pro');
      }
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
  /// [config] - MIDI playback configuration (defaults to exercise config)
  /// 
  /// Notes are scheduled relative to the current time, using the startEpochMs
  /// as a reference point for logging purposes only. Actual playback timing
  /// is based on Timer scheduling from method call time.
  Future<void> playSequence({
    required List<ReferenceNote> notes,
    double leadInSec = 0.0,
    required int runId,
    int? startEpochMs,
    MidiPlaybackConfig? config,
  }) async {
    final effectiveConfig = config ?? MidiPlaybackConfig.exercise();
    if (notes.isEmpty) {
      debugPrint('[ReferenceMidiSynth] No notes to play');
      return;
    }

    // Stop any existing playback (this will clear _activeNotes)
    await stop();

    // Ensure initialized with the correct SoundFont
    await init(config: effectiveConfig);
    if (_sfId == null) {
      debugPrint('[ReferenceMidiSynth] Cannot play notes: SoundFont not loaded');
      return;
    }

    // Log audio configuration (one line per playback call)
    if (notes.isNotEmpty) {
      final firstNote = notes.first;
      final firstNoteMidi = firstNote.midi.round();
      final firstNoteStartSec = firstNote.startSec;
      debugPrint(
          '[AudioConfig] mode=${effectiveConfig.debugTag} '
          'soundFont=${effectiveConfig.soundFontName} '
          'program=${effectiveConfig.program} bankMSB=${effectiveConfig.bankMSB} bankLSB=${effectiveConfig.bankLSB} '
          'channel=${effectiveConfig.channel} transpose=${effectiveConfig.transposeSemitones} '
          'volume=${effectiveConfig.volume.toStringAsFixed(2)} '
          'pitchBend=${effectiveConfig.enablePitchBend ? effectiveConfig.initialPitchBend : "center"} '
          'firstNoteMidi=$firstNoteMidi firstNoteStartSec=${firstNoteStartSec.toStringAsFixed(2)} noteCount=${notes.length}');
    }

    // Set current run ID and reset state
    _currentRunId = runId;
    _isPlaying = true;
    _activeNotes.clear(); // Ensure clean state (stop() should have cleared this, but be explicit)

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
    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
    
    // Calculate delay from timeline anchor epoch (if provided) or use current time
    // This ensures MIDI notes align with the visual timeline
    final timelineAnchorMs = startEpochMs ?? nowEpochMs;
    final delayFromAnchorMs = nowEpochMs - timelineAnchorMs;

    // Schedule each note using Timer
    for (final note in notes) {
      // Calculate note duration to distinguish endpoint markers from full notes
      final noteDuration = note.endSec - note.startSec;
      
      // Skip only endpoint markers (very short notes < 0.05s) that are marked as glides
      // Full-length notes marked as glides (like sirens) should still play
      if ((note.isGlideStart || note.isGlideEnd) && noteDuration < 0.05) {
        debugPrint('[ReferenceMidiSynth] Skipping glide endpoint marker: MIDI=${note.midi}, duration=${noteDuration.toStringAsFixed(3)}s');
        continue;
      }

      // Calculate absolute times relative to timeline anchor epoch
      // Notes have startSec that includes lead-in, so we schedule them at:
      // timelineAnchorMs + (note.startSec * 1000) - delayFromAnchorMs
      // This ensures notes play when the timeline reaches their startSec time
      final noteStartMsFromAnchor = (note.startSec * 1000).round();
      final noteEndMsFromAnchor = (note.endSec * 1000).round();
      final noteStartMs = noteStartMsFromAnchor - delayFromAnchorMs;
      final noteEndMs = noteEndMsFromAnchor - delayFromAnchorMs;
      
      // Guard against negative delays (shouldn't happen if notes have correct startSec)
      // If noteStartMs is negative, it means the note should have already played,
      // which indicates a timing issue (e.g., first note startSec is 0 instead of lead-in)
      if (noteStartMs < 0) {
        debugPrint(
            '[ReferenceMidiSynth] ERROR: Negative delay for note MIDI=${note.midi}, '
            'startSec=${note.startSec}, noteStartMsFromAnchor=$noteStartMsFromAnchor, '
            'delayFromAnchorMs=$delayFromAnchorMs, noteStartMs=$noteStartMs. '
            'This indicates first note startSec should include lead-in (~2.0s). '
            'Scheduling with 0ms delay (immediate playback - TIMING MISALIGNED).');
        // Don't schedule with negative delay - clamp to 0, but log the error
        // The sync check in exercise_player_screen should catch this
      }

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
          _activeNotes.add(note.midi); // Track that this note is now playing
          
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
          _activeNotes.remove(note.midi); // Remove from active notes set
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
    if (!_isPlaying && _activeNotes.isEmpty) return;

    _isPlaying = false;
    final timerCount = _activeTimers.length;
    final activeNoteCount = _activeNotes.length;
    _currentRunId = null;

    // Cancel all active timers
    for (final timer in _activeTimers) {
      timer.cancel();
    }
    _activeTimers.clear();

    // Stop all currently playing notes immediately
    final notesToStop = List<int>.from(_activeNotes);
    _activeNotes.clear();
    for (final midi in notesToStop) {
      try {
        _midi.stopMidiNote(midi: midi, velocity: 127);
      } catch (e) {
        debugPrint('[ReferenceMidiSynth] Error stopping note $midi during stop(): $e');
      }
    }

    debugPrint(
        '[ReferenceMidiSynth] Stopped playback (cancelled $timerCount timers, stopped $activeNoteCount active notes)');
  }

  /// Check if currently playing
  bool get isPlaying => _isPlaying;

  /// Get current run ID (for debugging)
  int? get currentRunId => _currentRunId;
}
