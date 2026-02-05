import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/reference_note.dart';
import '../../models/pitch_frame.dart';
import '../../services/pitch_highway_v2_session_controller.dart';
import '../../services/recording_service.dart';
import '../../services/audio_offset_estimator.dart';
import '../../services/vocal_range_service.dart'; // range
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/pitch_highway_painter.dart'; // painter
import '../../utils/pitch_tail_buffer.dart'; // TailPoint
import '../../utils/pitch_highway_tempo.dart'; // tempo

import '../../models/pitch_frame.dart'; // Ensure import

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
}

class _ReviewLastTakeV2ScreenState extends State<ReviewLastTakeV2Screen> {
  late PitchHighwayV2SessionController _controller;
  
  // Visualization State
  int _midiMin = 48;
  int _midiMax = 72;
  double _pixelsPerSecond = 100;
  final ValueNotifier<double> _visualTime = ValueNotifier(0.0);
  final ValueNotifier<double?> _liveMidi = ValueNotifier(null); // Not used in replay but required by painter

  @override
  void initState() {
    super.initState();
    _controller = PitchHighwayV2SessionController(
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
    final range = await VocalRangeService().getRange();
    if (mounted) {
      setState(() {
        _midiMin = range.$1 > 0 ? range.$1 : 48;
        _midiMax = range.$2 > 0 ? range.$2 : 72;
        // Approximation: Review usually uses same difficulty as play, but we don't have difficulty passed here.
        // Default to easy/medium speed ~100px/s or derive? 
        // PitchHighwayTempo.pixelsPerSecondFor(diff). 
        // Let's assume 100 which is standard.
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
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E), // Darker gray for DAW feel
      appBar: AppBar(
        title: const Text('Review Take', style: TextStyle(color: Colors.white70)),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white70),
      ),
      body: ValueListenableBuilder<PitchHighwaySessionState>(
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
                child: Container(
                  color: const Color(0xFFF5F5FA), // Light airy canvas
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
                                 drawBackground: true, // Grid
                                 midiMin: _midiMin,
                                 midiMax: _midiMax,
                                 isReviewMode: true, // NEW param to add to painter
                                 colors: AppThemeColors.light, // Light theme for canvas
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
                              colors: [Colors.white.withOpacity(0.9), Colors.white.withOpacity(0.0)],
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
              ),
              
              // --- 2. Bottom Section: Controls (35%) ---
              Expanded(
                flex: 35,
                child: Container(
                  color: const Color(0xFF121212), // Deep black/gray
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                            style: const TextStyle(
                              color: Colors.white, 
                              fontSize: 24, 
                              fontFamily: 'Monospace', 
                              fontWeight: FontWeight.w300
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
                                activeTrackColor: const Color(0xFF9C27B0), // Purple
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
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
                                color: Colors.white70,
                                iconSize: 28,
                                onPressed: () => _controller.seekTo(0),
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                icon: Icon(state.isPlayingReplay ? Icons.pause_circle_filled : Icons.play_circle_fill),
                                iconSize: 56,
                                color: Colors.white,
                                padding: EdgeInsets.zero,
                                onPressed: () => _controller.toggleReplay(),
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                icon: const Icon(Icons.loop_rounded), // Placeholder for loop logic if implemented
                                color: Colors.white24, // Disabled look for now
                                iconSize: 28,
                                onPressed: () {},
                              ),
                            ],
                          ),
                        ],
                      ),
                      
                      const Divider(color: Colors.white12, height: 12),
                      
                      // Alignment & Mix
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Offset: ${widget.offsetResult.offsetMs.toStringAsFixed(1)} ms",
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                              Row(
                                children: [
                                  Text("Active", style: TextStyle(color: state.applyOffset ? Colors.white : Colors.white24, fontSize: 12)),
                                  Transform.scale(
                                    scale: 0.8,
                                    child: Switch(
                                      value: state.applyOffset,
                                      onChanged: (v) => _controller.setApplyOffset(v),
                                      activeColor: const Color(0xFF9C27B0),
                                      activeTrackColor: const Color(0xFF9C27B0).withOpacity(0.5),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          // Mix Sliders (Compact)
                          Row(
                            children: [
                              const Text("Ref", style: TextStyle(color: Color(0xFFCE93D8), fontSize: 11)), // Light Purple
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 2,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                    activeTrackColor: const Color(0xFFCE93D8),
                                    thumbColor: const Color(0xFFCE93D8),
                                  ),
                                  child: Slider(
                                    value: state.refVolume, 
                                    onChanged: (v) => _controller.setRefVolume(v),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text("You", style: TextStyle(color: Color(0xFF90CAF9), fontSize: 11)), // Light Blue
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 2,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                    activeTrackColor: const Color(0xFF90CAF9),
                                    thumbColor: const Color(0xFF90CAF9),
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
    final paint = Paint()..color = Colors.black54..strokeWidth = 1.0;
    final textStyle = const TextStyle(color: Colors.black54, fontSize: 10);
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
