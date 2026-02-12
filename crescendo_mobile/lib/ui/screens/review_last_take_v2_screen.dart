import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/reference_note.dart';
import '../../models/pitch_frame.dart';
import '../../models/vocal_exercise.dart';
import '../../models/exercise_attempt.dart';
import '../../services/pitch_highway_session_controller.dart';
import '../../services/recording_service.dart';
import '../../services/audio_offset_estimator.dart';
import '../../services/vocal_range_service.dart'; // range
import '../../services/transposed_exercise_builder.dart';
import '../../services/attempt_repository.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/pitch_highway_painter.dart'; // painter
import '../../utils/pitch_tail_buffer.dart'; // TailPoint
import '../../theme/ballad_theme.dart';
import '../../widgets/ballad_scaffold.dart';
import '../../widgets/frosted_panel.dart';


class ReviewLastTakeV2Screen extends StatefulWidget {
  final List<ReferenceNote> notes;
  final String referencePath;
  final String recordingPath;
  final AudioOffsetResult offsetResult;
  final double referenceDurationSec;
  final List<PitchFrame> alignedFrames;

  const ReviewLastTakeV2Screen({
    super.key,
    required this.notes,
    required this.referencePath,
    required this.recordingPath,
    required this.offsetResult,
    required this.referenceDurationSec,
    required this.alignedFrames,
  });

  @override
  State<ReviewLastTakeV2Screen> createState() => _ReviewLastTakeV2ScreenState();

  /// Helper to fetch necessary data and push this screen
  static Future<void> loadAndPush(
    BuildContext context, {
    required VocalExercise exercise,
    required ExerciseAttempt attempt,
  }) async {
    final scaffold = ScaffoldMessenger.of(context);

    try {
      // 1. Resolve paths
      var audioPath = attempt.recordingPath;
      var contourJson = attempt.contourJson;
      var recorderStartSec = attempt.recorderStartSec;
      var referenceSampleRate = attempt.referenceSampleRate;

      if (audioPath == null || audioPath.isEmpty || !File(audioPath).existsSync()) {
        debugPrint('ReviewV2: recordingPath missing or invalid, trying recovery from last_take');
        final lastTake = await AttemptRepository.instance.loadLastTake(exercise.id);
        if (lastTake != null && File(lastTake.audioPath).existsSync()) {
          audioPath = lastTake.audioPath;
          recorderStartSec = lastTake.offsetMs / 1000.0;
          referenceSampleRate = lastTake.referenceSampleRate;
          
          if (contourJson == null) {
            final pf = File(lastTake.pitchPath);
            if (pf.existsSync()) {
              contourJson = await pf.readAsString();
            }
          }
        }
      }

      if (audioPath == null || audioPath.isEmpty || !File(audioPath).existsSync()) {
        throw 'Recording file not found';
      }

      // 2. Resolve reference path
      String? refPath = attempt.referenceWavPath;
      if (refPath == null || refPath.isEmpty) {
        debugPrint('ReviewV2: No reference path in attempt. Using empty fallback.');
      }
      
      // 3. Parse frames from contourJson
      List<PitchFrame> frames = [];
      if (contourJson != null && contourJson.isNotEmpty) {
        try {
           final List<dynamic> decoded = jsonDecode(contourJson);
           frames = decoded.map<PitchFrame>((f) => PitchFrame.fromJson(Map<String, dynamic>.from(f))).toList();
        } catch (e) {
           debugPrint('ReviewV2: Error parsing contourJson: $e');
        }
      }

      // 4. Build reference notes
      final range = await VocalRangeService().getRange();
      final sequence = TransposedExerciseBuilder.buildTransposedSequence(
        exercise: exercise,
        lowestMidi: range.$1,
        highestMidi: range.$2,
      );
      final notes = sequence.melody;

      if (!context.mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReviewLastTakeV2Screen(
            notes: notes,
            referencePath: refPath ?? '',
            recordingPath: audioPath!,
            offsetResult: AudioOffsetResult(
              offsetSamples: ((recorderStartSec ?? 0.0) * (referenceSampleRate ?? 44100)).round(),
              offsetMs: (recorderStartSec ?? 0.0) * 1000,
              confidence: (attempt.overallScore ?? 0) / 100.0,
              method: 'recovery',
            ),
            referenceDurationSec: exercise.estimatedDurationSec.toDouble(),
            alignedFrames: frames,
          ),
        ),
      );
    } catch (e) {
      scaffold.showSnackBar(SnackBar(content: Text('Error loading review: $e')));
    }
  }
}

class _ReviewLastTakeV2ScreenState extends State<ReviewLastTakeV2Screen> {
  late PitchHighwaySessionController _controller;
  
  // Visualization State
  int _midiMin = 48;
  int _midiMax = 72;
  double _pixelsPerSecond = 100;
  final ValueNotifier<double> _visualTime = ValueNotifier(0.0);
  final ValueNotifier<double?> _liveMidi = ValueNotifier(null); // Not used in replay but required by painter

  @override
  void initState() {
    super.initState();
    _controller = PitchHighwaySessionController(
      notes: widget.notes,
      referenceDurationSec: widget.referenceDurationSec,
      ensureReferenceWav: () async => widget.referencePath,
      ensureRecordingPath: () async => widget.recordingPath,
      recorderFactory: () => RecordingService(owner: 'review_v2', bufferSize: 1024),
    );
    
    // Hydrate state for replay
    _controller.state.value = _controller.state.value.copyWith(
      phase: PitchHighwaySessionPhase.replay,
      referencePath: widget.referencePath,
      recordingPath: widget.recordingPath,
      offsetResult: widget.offsetResult,
      applyOffset: true,
      alignedFrames: widget.alignedFrames,
      capturedFrames: widget.alignedFrames,
    );
    
    _loadData();
  }
  
  Future<void> _loadData() async {
    // Calculate range from notes
    int minMidi = 127;
    int maxMidi = 0;
    
    if (widget.notes.isNotEmpty) {
      for (final n in widget.notes) {
        if (n.midi < minMidi) minMidi = n.midi;
        if (n.midi > maxMidi) maxMidi = n.midi;
      }
    } else {
       // Fallback defaults
       minMidi = 48;
       maxMidi = 72;
    }

    // Add padding (e.g. +/- 3 semitones)
    minMidi -= 3;
    maxMidi += 3;

    if (mounted) {
      setState(() {
        _midiMin = minMidi;
        _midiMax = maxMidi;
        
        // Use standard speed
        _pixelsPerSecond = 100;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _visualTime.dispose();
    _liveMidi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors = [
      const Color(0xFF0e2763), // Lavender/Blue
      const Color(0xFF80CBC4), // Teal/Green
      const Color(0xFFB2DFDB), // Soft Aqua
    ];
    
    return BalladScaffold(
      title: 'Review Take',
      padding: EdgeInsets.zero, // Full-screen gradient
      child: Stack(
        children: [
          // Background gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: gradientColors,
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),
          // Main content
          ValueListenableBuilder<PitchHighwaySessionState>(
        valueListenable: _controller.state,
        builder: (context, state, _) {
          
          // Update visual time from replay time (which is driven by audio player)
          _visualTime.value = state.replayVisualTimeSec;
          
          final now = _visualTime.value;
          // Show a slightly wider window for review? or keep same as play?
          // Play shows 4s. Review could show more? Let's stick to 4s for consistency for now.
          final visibleFrames = state.alignedFrames.where((f) => f.time > now - 4.0 && f.time <= now);
          
          return Column(
            children: [
              // --- 1. Top Section: Pitch Lane (65%) ---
              Expanded(
                flex: 65,
                child: Stack(
                    children: [
                      // Pitch Highway
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                             // Map frames to visual points
                             final points = visibleFrames.map((f) {
                                final midi = f.midi ?? 0;
                                // Map MIDI to Y. High MIDI = Low Y (Top).
                                final y = (constraints.maxHeight) - ((midi - _midiMin) / (_midiMax - _midiMin)) * constraints.maxHeight;
                                return TailPoint(tSec: f.time, yPx: y, voiced: (f.voicedProb??0) > 0.5); 
                             }).toList();
  
                             return CustomPaint(
                               painter: PitchHighwayPainter(
                                 notes: widget.notes,
                                 pitchTail: const [], // We use tailPoints for pre-recorded
                                 tailPoints: points,
                                 time: _visualTime,
                                 liveMidi: _liveMidi, // Not used in review but required
                                 pitchTailTimeOffsetSec: 0,
                                 pixelsPerSecond: _pixelsPerSecond,
                                 playheadFraction: 0.45,
                                 drawBackground: false, // Disable grid to allow scrolling
                                 midiMin: _midiMin,
                                 midiMax: _midiMax,
                                 isReviewMode: true,
                                 colors: AppThemeColors.dark,
                               ),
                             );
                          }
                        ),
                      ),
                      
                      // Top Ruler (Simple overlay for now)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 24,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [BalladTheme.bgTop.withOpacity(0.9), BalladTheme.bgTop.withOpacity(0.0)],
                            ),
                          ),
                          child: CustomPaint(
                            painter: _TimeRulerPainter(
                              time: now, 
                              pixelsPerSecond: _pixelsPerSecond, 
                              playheadFraction: 0.45
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ),
              
              // --- 2. Bottom Section: Controls (35%) ---
              Expanded(
                flex: 35,
                child: FrostedPanel(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Time Transport
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Time Display
                          Text(
                            _formatTime(now),
                            style: BalladTheme.titleLarge.copyWith(
                              fontSize: 32, 
                              fontWeight: FontWeight.w300,
                              letterSpacing: -1.0,
                            )
                          ),
                          const SizedBox(height: 4),
                          // Scrub Bar
                          SizedBox(
                            height: 20,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                activeTrackColor: BalladTheme.accentLavender.withOpacity(0.3),
                                inactiveTrackColor: Colors.white24,
                                thumbColor: BalladTheme.accentLavender,
                              ),
                              child: Slider(
                                value: now.clamp(0.0, widget.referenceDurationSec),
                                min: 0.0,
                                max: widget.referenceDurationSec,
                                onChanged: (v) => _controller.seekTo(v),
                              ),
                            ),
                          ),
                          // Transport Buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.skip_previous_rounded),
                                color: BalladTheme.accentLavender,
                                iconSize: 32,
                                onPressed: () => _controller.seekTo(0),
                              ),
                              const SizedBox(width: 24),
                              GestureDetector(
                                onTap: () => _controller.toggleReplay(),
                                child: Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: BalladTheme.accentPurple,
                                    borderRadius: BorderRadius.circular(32),
                                    boxShadow: [
                                      BoxShadow(
                                        color: BalladTheme.accentPurple.withOpacity(0.4),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      )
                                    ],
                                  ),
                                  child: Icon(
                                    state.isPlayingReplay ? Icons.pause_rounded : Icons.play_arrow_rounded, 
                                    size: 40, 
                                    color: Colors.white
                                  ),
                                ),
                              ),
                              const SizedBox(width: 24),
                              IconButton(
                                icon: const Icon(Icons.loop_rounded),
                                color: Colors.black12, 
                                iconSize: 32,
                                onPressed: () {},
                              ),
                            ],
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 8),
                      
                      // Alignment & Mix
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Offset: ${widget.offsetResult.offsetMs.toStringAsFixed(1)} ms",
                                style: BalladTheme.bodySmall.copyWith(color: BalladTheme.textSecondary),
                              ),
                              Row(
                                children: [
                                Text("Align", style: TextStyle(color: state.applyOffset ? BalladTheme.accentLavender : BalladTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 8),
                                  Transform.scale(
                                    scale: 0.8,
                                    child: Switch(
                                      value: state.applyOffset,
                                      onChanged: (v) => _controller.setApplyOffset(v),
                                      activeColor: Colors.white,
                                      activeTrackColor: BalladTheme.accentLavender,
                                      inactiveThumbColor: Colors.white,
                                      inactiveTrackColor: Colors.white10,
                                      trackOutlineColor: MaterialStateProperty.all(Colors.transparent),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          // Mix Sliders (Compact)
                          Row(
                            children: [
                              const Text("Ref", style: TextStyle(color: BalladTheme.accentLavender, fontSize: 11)), // Unified color
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 2,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                    activeTrackColor: BalladTheme.accentLavender.withOpacity(0.5),
                                    thumbColor: BalladTheme.accentLavender,
                                  ),
                                  child: Slider(
                                    value: state.refVolume, 
                                    onChanged: (v) => _controller.setRefVolume(v),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text("You", style: TextStyle(color: BalladTheme.accentLavender, fontSize: 11)), // Unified color
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 2,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                    activeTrackColor: BalladTheme.accentLavender.withOpacity(0.5),
                                    thumbColor: BalladTheme.accentLavender,
                                  ),
                                  child: Slider(
                                    value: state.recVolume, 
                                    onChanged: (v) => _controller.setRecVolume(v),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
        ],
      ),
    );
  }

  String _formatTime(double sec) {
    final int min = sec ~/ 60;
    final int s = sec.floor() % 60;
    final int ms = ((sec - sec.floor()) * 100).floor();
    return "$min:${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}";
  }
}

class _TimeRulerPainter extends CustomPainter {
  final double time;
  final double pixelsPerSecond;
  final double playheadFraction;

  _TimeRulerPainter({required this.time, required this.pixelsPerSecond, required this.playheadFraction});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white54..strokeWidth = 1.0;
    final textStyle = const TextStyle(color: Colors.white54, fontSize: 10);
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    
    // Draw ticks every 1 second
    final startVisibleTime = time - (size.width * playheadFraction) / pixelsPerSecond;
    final endVisibleTime = time + (size.width * (1-playheadFraction)) / pixelsPerSecond;
    
    final startSec = startVisibleTime.floor();
    final endSec = endVisibleTime.ceil();
    
    for (int s = startSec; s <= endSec; s++) {
      if (s < 0) continue;
      final x = (size.width * playheadFraction) + (s - time) * pixelsPerSecond;
      
      canvas.drawLine(Offset(x, 0), Offset(x, 10), paint);
      
      textPainter.text = TextSpan(text: "$s:00", style: textStyle);
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + 4, 0));
    }
  }

  @override
  bool shouldRepaint(covariant _TimeRulerPainter old) => old.time != time;
}
