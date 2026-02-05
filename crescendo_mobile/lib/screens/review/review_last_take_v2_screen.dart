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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Review Last Take (V2)'),
        backgroundColor: Colors.transparent,
      ),
      body: ValueListenableBuilder<PitchHighwaySessionState>(
        valueListenable: _controller.state,
        builder: (context, state, _) {
          
          // Update visual time from replay time (which is driven by audio player)
          _visualTime.value = state.replayVisualTimeSec;
          
          final now = _visualTime.value;
          final visibleFrames = state.alignedFrames.where((f) => f.time > now - 4.0 && f.time <= now);
          
          return Stack(
            children: [
               // 1. Pitch Highway Visualization
               Positioned.fill(
                 child: LayoutBuilder(
                   builder: (context, constraints) {
                      final points = visibleFrames.map((f) {
                         final midi = f.midi ?? 0;
                         // Map MIDI to Y pixels (inverted, higher pitch = higher Y? wait, Layout Y=0 is TOP. High pitch = LOW Y)
                         // V2 Player logic: (constraints.maxHeight) - ((midi - _midiMin) / (_midiMax - _midiMin)) * constraints.maxHeight;
                         // This means High Midi => High Value => (1.0) => Y = 0 (Top). Correct.
                         final y = (constraints.maxHeight) - ((midi - _midiMin) / (_midiMax - _midiMin)) * constraints.maxHeight;
                         return TailPoint(tSec: f.time, yPx: y, voiced: (f.voicedProb??0) > 0.5); 
                      }).toList();

                      return CustomPaint(
                        painter: PitchHighwayPainter(
                          notes: widget.notes,
                          pitchTail: const [], // We use tailPoints for pre-recorded
                          tailPoints: points,
                          time: _visualTime,
                          liveMidi: _liveMidi,
                          pitchTailTimeOffsetSec: 0,
                          pixelsPerSecond: _pixelsPerSecond,
                          playheadFraction: 0.45,
                          drawBackground: true,
                          midiMin: _midiMin,
                          midiMax: _midiMax,
                          colors: AppThemeColors.of(context),
                        ),
                      );
                   }
                 ),
               ),
               
               // 2. Controls Overlay
               // We put them in a column, but maybe semitransparent background?
               Align(
                 alignment: Alignment.bottomCenter,
                 child: Container(
                   color: Colors.black54,
                   padding: const EdgeInsets.all(16.0),
                   child: Column(
                     mainAxisSize: MainAxisSize.min,
                     children: [
                        Text(
                          "Offset: ${widget.offsetResult.offsetMs.toStringAsFixed(1)} ms", 
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                        ),
                        
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: Icon(state.isPlayingReplay ? Icons.stop_circle : Icons.play_circle_fill),
                              iconSize: 64,
                              color: state.isPlayingReplay ? Colors.red : Colors.green,
                              onPressed: () => _controller.toggleReplay(),
                            ),
                          ],
                        ),
                        
                        SwitchListTile(
                          title: const Text("Apply Alignment", style: TextStyle(color: Colors.white)),
                          value: state.applyOffset,
                          onChanged: (v) => _controller.setApplyOffset(v),
                          activeColor: AppThemeColors.of(context).accentBlue,
                        ),
                       Row(
                          children: [
                            const Text("Ref Vol", style: TextStyle(color: Colors.white)),
                            Expanded(child: Slider(
                              value: state.refVolume, 
                              onChanged: (v) => _controller.setRefVolume(v),
                              activeColor: AppThemeColors.of(context).accentPurple,
                            )),
                          ],
                        ),
                       Row(
                          children: [
                            const Text("Rec Vol", style: TextStyle(color: Colors.white)),
                            Expanded(child: Slider(
                              value: state.recVolume, 
                              onChanged: (v) => _controller.setRecVolume(v),
                              activeColor: AppThemeColors.of(context).accentBlue,
                            )),
                          ],
                        ),
                        
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(), 
                          child: const Text("Done")
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
}
