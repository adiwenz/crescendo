import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';

import '../../models/last_take.dart';
import '../../models/pitch_highway_difficulty.dart';
import '../../models/reference_note.dart';
import '../../models/vocal_exercise.dart';
import '../../models/siren_path.dart';
import '../../services/audio_synth_service.dart';
import '../../services/transposed_exercise_builder.dart';
import '../../services/vocal_range_service.dart';
import '../../utils/pitch_highway_tempo.dart';
import '../../utils/pitch_math.dart';
import '../../utils/performance_clock.dart';
import '../../utils/exercise_constants.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/pitch_contour_painter.dart';
import '../widgets/pitch_highway_painter.dart';

class PitchHighwayReviewScreen extends StatefulWidget {
  final VocalExercise exercise;
  final LastTake lastTake;
  final double startTimeSec;

  const PitchHighwayReviewScreen({
    super.key,
    required this.exercise,
    required this.lastTake,
    this.startTimeSec = 0.0,
  });

  @override
  State<PitchHighwayReviewScreen> createState() => _PitchHighwayReviewScreenState();
}

class _PitchHighwayReviewScreenState extends State<PitchHighwayReviewScreen>
    with SingleTickerProviderStateMixin {
  // Enable mixing mode to play both recorded audio and reference notes simultaneously
  final AudioSynthService _synth = AudioSynthService(enableMixing: true);
  final VocalRangeService _vocalRangeService = VocalRangeService();
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  final PerformanceClock _clock = PerformanceClock();
  Ticker? _ticker;
  bool _playing = false;
  StreamSubscription<Duration>? _audioPosSub;
  StreamSubscription<void>? _audioCompleteSub;
  double? _audioPositionSec;
  bool _audioStarted = false;
  List<ReferenceNote> _notes = const [];
  SirenPath? _sirenVisualPath; // Visual path for Sirens (separate from audio notes)
  double _durationSec = 1.0;
  // Use shared constant for lead-in time
  static const double _leadInSec = ExerciseConstants.leadInSec;
  bool _loggedGraphInfo = false;
  late final double _pixelsPerSecond;
  
  // Preload state
  bool _preloadComplete = false;
  bool _preloading = false;
  String? _referenceAudioPath;
  String? _recordedAudioPath;
  DateTime? _playbackStartEpoch; // Exact moment playback truly starts
  int _lastSyncLogTime = 0;

  @override
  void initState() {
    super.initState();
    final difficulty =
        pitchHighwayDifficultyFromName(widget.lastTake.pitchDifficulty) ??
            PitchHighwayDifficulty.medium;
    _pixelsPerSecond = PitchHighwayTempo.pixelsPerSecondFor(difficulty);
    _ticker = createTicker(_onTick);
    _clock.setAudioPositionProvider(() => _audioPositionSec);
    // In review mode, audio position is already accurate (from playback), so no latency compensation needed
    _clock.setLatencyCompensationMs(0);
    _time.value = widget.startTimeSec;
    _preloadEverything(difficulty);
  }
  
  /// Preload everything before allowing playback
  Future<void> _preloadEverything(PitchHighwayDifficulty difficulty) async {
    if (_preloading) return;
    _preloading = true;
    
    final tapTime = DateTime.now().millisecondsSinceEpoch;
    if (kDebugMode) {
      debugPrint('[Review Preload] tapTime=$tapTime (preload started)');
    }
    
    // Step 1: Load transposed notes
    await _loadTransposedNotes(difficulty);
    
    // Step 2: Render reference notes audio (this is the expensive operation)
    if (_notes.isNotEmpty) {
      _referenceAudioPath = await _synth.renderReferenceNotes(_notes);
      if (kDebugMode) {
        debugPrint('[Review Preload] Reference audio rendered: ${_referenceAudioPath}');
      }
    }
    
    // Step 3: Check recorded audio
    final audioPath = widget.lastTake.audioPath;
    if (audioPath != null && audioPath.isNotEmpty) {
      final file = File(audioPath);
      if (await file.exists()) {
        _recordedAudioPath = audioPath;
        if (kDebugMode) {
          debugPrint('[Review Preload] Recorded audio found: ${_recordedAudioPath}');
        }
      }
    }
    
    // Step 4: Warm up audio engine (silent warmup)
    await _warmupAudioEngine();
    
    final preloadCompleteTime = DateTime.now().millisecondsSinceEpoch;
    if (kDebugMode) {
      debugPrint('[Review Preload] preloadCompleteTime=$preloadCompleteTime (preload finished, took ${preloadCompleteTime - tapTime}ms)');
    }
    
    if (mounted) {
      setState(() {
        _preloadComplete = true;
        _preloading = false;
      });
      
      // Auto-start playback immediately once preload is complete
      // Use SchedulerBinding to ensure this runs after the frame is built
      if (_notes.isNotEmpty && !_playing) {
        if (kDebugMode) {
          debugPrint('[Review] Preload complete, attempting auto-start: notes=${_notes.length}, playing=$_playing');
        }
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_playing && _preloadComplete && _notes.isNotEmpty) {
            if (kDebugMode) {
              debugPrint('[Review] Auto-starting playback: notes=${_notes.length}, preloadComplete=$_preloadComplete');
            }
            _start();
          } else if (kDebugMode) {
            debugPrint('[Review] Auto-start skipped: mounted=$mounted, playing=$_playing, preloadComplete=$_preloadComplete, notesEmpty=${_notes.isEmpty}');
          }
        });
      } else if (kDebugMode && _notes.isEmpty) {
        debugPrint('[Review] WARNING: Preload complete but notes are empty!');
      }
    }
  }
  
  /// Warm up the audio engine to eliminate first-play latency
  Future<void> _warmupAudioEngine() async {
    try {
      // Render a very short silent audio clip to warm up the engine
      final warmupNotes = [
        ReferenceNote(startSec: 0, endSec: 0.05, midi: 60), // 50ms silent note
      ];
      final warmupPath = await _synth.renderReferenceNotes(warmupNotes);
      // Play it at very low volume (or we could just load it without playing)
      // Actually, just loading it should warm up the engine
      // We'll dispose of it immediately
      final warmupFile = File(warmupPath);
      if (await warmupFile.exists()) {
        // Just touch the file to ensure it's ready - the act of rendering already warmed up
        await warmupFile.delete(); // Clean up
      }
      if (kDebugMode) {
        debugPrint('[Review Preload] Audio engine warmed up');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Review Preload] Warmup error (non-fatal): $e');
      }
    }
  }

  Future<void> _loadTransposedNotes(PitchHighwayDifficulty difficulty) async {
    final (lowestMidi, highestMidi) = await _vocalRangeService.getRange();
    
    // Special handling for Sirens: use buildSirensWithVisualPath to get both audio notes and visual path
    final List<ReferenceNote> notes;
    SirenPath? sirenPath;
    if (widget.exercise.id == 'sirens') {
      final sirenResult = TransposedExerciseBuilder.buildSirensWithVisualPath(
        exercise: widget.exercise,
        lowestMidi: lowestMidi,
        highestMidi: highestMidi,
        leadInSec: _leadInSec,
        difficulty: difficulty,
      );
      notes = sirenResult.audioNotes; // Get the 3 audio notes for playback
      sirenPath = sirenResult.visualPath; // Get the visual bell curve path
    } else {
      notes = TransposedExerciseBuilder.buildTransposedSequence(
        exercise: widget.exercise,
        lowestMidi: lowestMidi,
        highestMidi: highestMidi,
        leadInSec: _leadInSec,
        difficulty: difficulty,
      );
      sirenPath = null;
    }
    
    if (mounted) {
      setState(() {
        _notes = notes;
        _sirenVisualPath = sirenPath; // Store visual path for Sirens
        _durationSec = _computeDuration(notes);
      });
      
      // Try to auto-start if preload is already complete
      // Otherwise, preload completion will trigger auto-start
      if (notes.isNotEmpty && !_playing && _preloadComplete) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_playing && _notes.isNotEmpty && _preloadComplete) {
            if (kDebugMode) {
              debugPrint('[Review] Auto-starting from notes loaded: notes=${_notes.length}');
            }
            _start();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _audioPosSub?.cancel();
    _audioCompleteSub?.cancel();
    _synth.stop();
    _time.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_playing) return;
    
    // Use audio position as master clock - visuals MUST follow audio
    // If audio position is not available, freeze visuals
    if (_audioPositionSec == null) {
      // Don't advance visuals until audio starts
      return;
    }
    
    // Visual time is driven directly by audio position (master clock)
    final visualTimeMs = _audioPositionSec! * 1000.0;
    _time.value = _audioPositionSec!;
    
    // Debug logging (temporary) - log every 250-500ms
    if (kDebugMode) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastSyncLogTime >= 250) {
        _lastSyncLogTime = now;
        final audioTimeMs = _audioPositionSec! * 1000.0;
        final diffMs = visualTimeMs - audioTimeMs; // Should be 0
        debugPrint('[Review Sync] visualTimeMs=${visualTimeMs.toStringAsFixed(1)}, '
            'audioTimeMs=${audioTimeMs.toStringAsFixed(1)}, diffMs=${diffMs.toStringAsFixed(1)}');
        
        // Assert sync after first second
        if (_time.value > 1.0 && diffMs.abs() > 50) {
          debugPrint('[Review Sync WARNING] Desync detected: ${diffMs.toStringAsFixed(1)}ms');
        }
      }
    }
    
    if (_audioPositionSec! >= _durationSec) {
      _stop();
    }
  }

  Future<void> _start() async {
    if (_playing || !_preloadComplete) return;
    
    final tapTime = DateTime.now().millisecondsSinceEpoch;
    final startOffsetSec = widget.startTimeSec;
    
    if (kDebugMode) {
      debugPrint('[Review Start] tapTime=$tapTime (playback requested), startOffsetSec=$startOffsetSec');
    }
    
    // Set visual time to start offset immediately (before audio starts)
    _time.value = startOffsetSec;
    
    if (kDebugMode) {
      debugPrint('[Review] visualsSeeked=true at ${startOffsetSec.toStringAsFixed(2)}s');
    }
    
    _playing = true;
    _audioPositionSec = startOffsetSec; // Initialize to start offset
    _audioStarted = false;
    
    // Reset clock - visuals will be driven directly by audio position
    _clock.setLatencyCompensationMs(0);
    _clock.start(offsetSec: startOffsetSec, freezeUntilAudio: true);
    
    // Start ticker - it will update visuals from audio position
    _ticker?.start();
    
    // Capture exact playback start moment (this is the master clock anchor)
    _playbackStartEpoch = DateTime.now();
    final playbackStartTime = _playbackStartEpoch!.millisecondsSinceEpoch;
    
    if (kDebugMode) {
      debugPrint('[Review Start] playbackStartEpoch=$playbackStartTime, '
          'startOffsetSec=$startOffsetSec, LEAD_IN_MS=${ExerciseConstants.leadInMs}');
    }
    
    // Start audio playback immediately (everything is preloaded)
    // Audio will be sought to startOffsetSec in _playAudio()
    await _playAudio();
    
    final midiEngineStartTime = DateTime.now().millisecondsSinceEpoch;
    if (kDebugMode) {
      debugPrint('[Review Start] midiEngineStartTime=$midiEngineStartTime, '
          'latency=${midiEngineStartTime - playbackStartTime}ms');
      if (_notes.isNotEmpty) {
        // Find first note that's >= startOffsetSec
        final relevantNotes = _notes.where((n) => n.startSec >= startOffsetSec).toList();
        if (relevantNotes.isNotEmpty) {
          final firstNoteStartMs = relevantNotes.first.startSec * 1000.0;
          debugPrint('[Review Start] firstMidiNoteAfterOffset=${firstNoteStartMs}ms (offset=$startOffsetSec)');
        }
      }
    }
    
    if (mounted) setState(() {});
  }

  Future<void> _stop() async {
    if (!_playing) return;
    _playing = false;
    _ticker?.stop();
    _clock.pause();
    // Stop audio immediately - this will stop audio position updates
    await _synth.stop();
    await _audioPosSub?.cancel();
    _audioPosSub = null;
    await _audioCompleteSub?.cancel();
    _audioCompleteSub = null;
    _audioPositionSec = null;
    _audioStarted = false;
    if (mounted) setState(() {});
  }
  
  /// Called when primary recording playback completes
  Future<void> _onPlaybackComplete() async {
    if (kDebugMode) {
      debugPrint('[Review] Primary recording playback completed');
    }
    // Stop both MIDI and recorded audio
    await _stop();
    // Navigate back to previous screen
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _playAudio() async {
    // Seek to the start time before playing (if startTimeSec > 0)
    final startOffsetSec = widget.startTimeSec;
    
    if (kDebugMode) {
      debugPrint('[Review] startOffsetSec=$startOffsetSec');
    }
    
    final hasRecordedAudio = _recordedAudioPath != null && _recordedAudioPath!.isNotEmpty;
    
    // Always play reference notes (MIDI guide tones)
    // If recorded audio exists, play it simultaneously
    if (hasRecordedAudio) {
      // Play both recorded audio and reference notes simultaneously
      // Reference notes on secondary player, recorded audio on primary player
      await _playReference(useSecondaryPlayer: true); // Start reference notes on secondary
      await _synth.playFile(_recordedAudioPath!); // Then start recorded audio on primary
      
      // Seek both players to the start offset
      if (startOffsetSec > 0) {
        final seekPos = Duration(milliseconds: (startOffsetSec * 1000).round());
        await _synth.seek(seekPos);
        await _synth.seekSecondary(seekPos);
        if (kDebugMode) {
          debugPrint('[Review] audioSeeked=true at ${startOffsetSec.toStringAsFixed(2)}s');
        }
      }
      
      // Debug: log when audio actually starts
      if (kDebugMode) {
        final t0AudioStart = DateTime.now().millisecondsSinceEpoch;
        debugPrint('[Review Start] t0_audioStart=$t0AudioStart (recorded audio + reference notes playback began)');
      }
      
      // Use primary player's position (recorded audio) as master clock
        await _audioPosSub?.cancel();
        _audioPosSub = _synth.onPositionChanged.listen((pos) {
          if (!_audioStarted && pos > Duration.zero) {
            _audioStarted = true;
          // Debug: log when audio position first becomes available
          if (kDebugMode) {
            debugPrint('[Review Start] Audio position stream started, first pos=${pos.inMilliseconds}ms');
          }
          }
        if (_audioStarted) {
          // Audio position is relative to audio file start
          // Add the start offset to get the actual timeline position
          _audioPositionSec = (pos.inMilliseconds / 1000.0) + startOffsetSec;
          
          // Visual time is driven directly by audio position (master clock)
          // This ensures perfect sync
        }
      });
      
      // Listen for primary recording completion
      await _audioCompleteSub?.cancel();
      _audioCompleteSub = _synth.onComplete.listen((_) {
        _onPlaybackComplete();
      });
    } else {
      // No recorded audio, just play reference notes
      await _playReference();
      
      // Seek to the start offset
      if (startOffsetSec > 0) {
        final seekPos = Duration(milliseconds: (startOffsetSec * 1000).round());
        await _synth.seek(seekPos);
        if (kDebugMode) {
          debugPrint('[Review] audioSeeked=true at ${startOffsetSec.toStringAsFixed(2)}s');
        }
      }
    }
    
    if (kDebugMode) {
      debugPrint('[Review] playbackStartedAt=${startOffsetSec.toStringAsFixed(2)}s');
    }
  }

  Future<void> _playReference({bool useSecondaryPlayer = false}) async {
    if (_notes.isEmpty || _referenceAudioPath == null) return;
    
    // Use pre-rendered audio path (from preload)
    final path = _referenceAudioPath!;
    // Reference notes already have lead-in built in (first note starts at leadInSec)
    // So audio will have 2 seconds of silence at the start, which matches the visual lead-in
    
    // Use secondary player if mixing with recorded audio, otherwise primary player
    if (useSecondaryPlayer) {
      await _synth.playSecondaryFile(path);
    } else {
    await _synth.playFile(path);
    }
    
    // Debug: log when reference audio starts
    if (kDebugMode) {
      final t0AudioStart = DateTime.now().millisecondsSinceEpoch;
      debugPrint('[Review Start] t0_audioStart=$t0AudioStart (reference audio playback began)');
    }
    
    // Only set up position listener if we're not already listening to recorded audio
    // (i.e., when useSecondaryPlayer is false, meaning we're playing reference only)
    if (!useSecondaryPlayer) {
    await _audioPosSub?.cancel();
    _audioPosSub = _synth.onPositionChanged.listen((pos) {
      if (!_audioStarted && pos > Duration.zero) {
        _audioStarted = true;
          // Debug: log when audio position first becomes available
          if (kDebugMode) {
            debugPrint('[Review Start] Audio position stream started, first pos=${pos.inMilliseconds}ms');
          }
      }
      if (_audioStarted) {
          // Audio position is relative to audio file start, which includes lead-in silence
          // Chart time also includes lead-in, so they should be in sync
        _audioPositionSec = pos.inMilliseconds / 1000.0;
          
          // Visual time is driven directly by audio position (master clock)
          // This ensures perfect sync
      }
    });
    
    // Listen for reference notes completion (when no recorded audio)
    await _audioCompleteSub?.cancel();
    _audioCompleteSub = _synth.onComplete.listen((_) {
      _onPlaybackComplete();
    });
    }
  }

  double _computeDuration(List<ReferenceNote> notes) {
    final specDuration =
        notes.isEmpty ? 0.0 : notes.map((n) => n.endSec).fold(0.0, math.max);
    return math.max(widget.lastTake.durationSec, specDuration) +
        AudioSynthService.tailSeconds;
  }


  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    final noteMidis = _notes.map((n) => n.midi.toDouble()).toList();
    final contourMidis = widget.lastTake.frames
        .map((f) => f.midi ?? (f.hz != null ? PitchMath.hzToMidi(f.hz!) : null))
        .whereType<double>()
        .toList();
    
    // For Sirens, use visual path for MIDI range (more accurate)
    final minMidi = widget.exercise.id == 'sirens' && _sirenVisualPath != null && _sirenVisualPath!.points.isNotEmpty
        ? (_sirenVisualPath!.points.map((p) => p.midiFloat).reduce((a, b) => a < b ? a : b).floor() - 3)
        : (noteMidis.isNotEmpty || contourMidis.isNotEmpty
            ? ([...noteMidis, ...contourMidis].reduce(math.min).floor() - 3)
            : 48);
    final maxMidi = widget.exercise.id == 'sirens' && _sirenVisualPath != null && _sirenVisualPath!.points.isNotEmpty
        ? (_sirenVisualPath!.points.map((p) => p.midiFloat).reduce((a, b) => a > b ? a : b).ceil() + 3)
        : (noteMidis.isNotEmpty || contourMidis.isNotEmpty
            ? ([...noteMidis, ...contourMidis].reduce(math.max).ceil() + 3)
            : 72);
    assert(() {
      debugPrint('[Review] exerciseId: ${widget.lastTake.exerciseId}');
      if (noteMidis.isNotEmpty) {
        debugPrint('[Review] note midi range: '
            '${noteMidis.reduce(math.min)}..${noteMidis.reduce(math.max)}');
      }
      if (contourMidis.isNotEmpty) {
        debugPrint('[Review] contour midi range: '
            '${contourMidis.reduce(math.min)}..${contourMidis.reduce(math.max)}');
      }
      debugPrint('[Review] viewport midi: $minMidi..$maxMidi');
      return true;
    }());
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Review last take'),
      ),
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _playing
                ? _stop
                : (_preloadComplete ? _start : () {}), // Disabled until preload complete
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (kDebugMode && !_loggedGraphInfo) {
                  debugPrint(
                    'REVIEW GRAPH: height=${constraints.maxHeight} '
                    'topPad=0.0 bottomPad=0.0 '
                    'viewportMinMidi=$minMidi viewportMaxMidi=$maxMidi',
                  );
                  _loggedGraphInfo = true;
                }
                return Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: PitchHighwayPainter(
                          notes: _notes,
                          pitchTail: widget.lastTake.frames,
                          time: _time,
                          pixelsPerSecond: _pixelsPerSecond,
                          playheadFraction: 0.45,
                          smoothingWindowSec: 0.12,
                          drawBackground: false,
                          showLivePitch: false,
                          showPlayheadLine: false,
                          midiMin: minMidi,
                          midiMax: maxMidi,
                          colors: colors,
                          debugLogMapping: true,
                          sirenPath: _sirenVisualPath, // Pass visual path for Sirens bell curve
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: PitchContourPainter(
                          frames: widget.lastTake.frames,
                          time: _time,
                          pixelsPerSecond: _pixelsPerSecond,
                          playheadFraction: 0.45,
                          midiMin: minMidi,
                          midiMax: maxMidi,
                          glowColor: colors.goldAccent,
                          coreColor: colors.goldAccent,
                          debugLogMapping: true,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _PlayheadPainter(
                          playheadFraction: 0.45,
                          lineColor: colors.blueAccent.withOpacity(0.7),
                          shadowColor: Colors.black.withOpacity(0.3),
                        ),
                      ),
                    ),
                    if (kDebugMode && _notes.isNotEmpty)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _DebugYLinePainter(
                            midi: _notes.first.midi.toDouble(),
                            midiMin: minMidi,
                            midiMax: maxMidi,
                            color: Colors.red.withOpacity(0.5),
                          ),
                        ),
                      ),
                    // Loading overlay
                    if (!_preloadComplete)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withOpacity(0.7),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                Text(
                                  'Loading...',
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayheadPainter extends CustomPainter {
  final double playheadFraction;
  final Color lineColor;
  final Color shadowColor;

  const _PlayheadPainter({
    required this.playheadFraction,
    required this.lineColor,
    required this.shadowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * playheadFraction;
    final shadowPaint = Paint()
      ..color = shadowColor
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(x + 0.5, 0), Offset(x + 0.5, size.height), shadowPaint);
    final playheadPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), playheadPaint);
  }

  @override
  bool shouldRepaint(covariant _PlayheadPainter oldDelegate) {
    return oldDelegate.playheadFraction != playheadFraction;
  }
}

class _DebugYLinePainter extends CustomPainter {
  final double midi;
  final int midiMin;
  final int midiMax;
  final Color color;

  _DebugYLinePainter({
    required this.midi,
    required this.midiMin,
    required this.midiMax,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final y = PitchMath.midiToY(
      midi: midi,
      height: size.height,
      midiMin: midiMin,
      midiMax: midiMax,
    );
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }

  @override
  bool shouldRepaint(covariant _DebugYLinePainter oldDelegate) {
    return oldDelegate.midi != midi ||
        oldDelegate.midiMin != midiMin ||
        oldDelegate.midiMax != midiMax ||
        oldDelegate.color != color;
  }
}
