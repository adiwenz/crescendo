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
      backgroundColor: const Color(0xFFF9F9FC), // Soft lavender/white tint
      appBar: AppBar(
        title: const Text('Review Take', style: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.w600)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: const Color(0xFF1A1A1A),
          onPressed: () => Navigator.of(context).pop(),
        ),
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
                  color: Colors.transparent, // Let scaffold bg show through
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
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 20,
                        offset: Offset(0, -5),
                      ),
                    ],
                  ),
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
                            style: const TextStyle(
                              color: Color(0xFF1A1A1A), 
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
                                activeTrackColor: const Color(0xFF8055E3).withOpacity(0.3), // User requested #8055e3
                                inactiveTrackColor: const Color(0xFFE0E0E0),
                                thumbColor: const Color(0xFF8055E3),
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
                                color: const Color(0xFF8055E3),
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
                                    color: const Color(0xFF8055E3),
                                    borderRadius: BorderRadius.circular(32),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF8055E3).withOpacity(0.4),
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
                                style: const TextStyle(color: Colors.black45, fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                              Row(
                                children: [
                                  Text("Align", style: TextStyle(color: state.applyOffset ? const Color(0xFF8055E3) : Colors.black26, fontSize: 13, fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 8),
                                  Transform.scale(
                                    scale: 0.8,
                                    child: Switch(
                                      value: state.applyOffset,
                                      onChanged: (v) => _controller.setApplyOffset(v),
                                      activeColor: Colors.white,
                                      activeTrackColor: const Color(0xFF8055E3),
                                      inactiveThumbColor: Colors.white,
                                      inactiveTrackColor: Colors.grey.shade300,
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
