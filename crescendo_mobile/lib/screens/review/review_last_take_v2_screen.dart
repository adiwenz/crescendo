import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/reference_note.dart';
import '../../services/pitch_highway_v2_session_controller.dart';
import '../../services/recording_service.dart';
import '../../services/audio_offset_estimator.dart';
import '../../ui/theme/app_theme.dart';

class ReviewLastTakeV2Screen extends StatefulWidget {
  final List<ReferenceNote> notes;
  final String referencePath;
  final String recordingPath;
  final AudioOffsetResult offsetResult;
  final double referenceDurationSec;

  const ReviewLastTakeV2Screen({
    super.key,
    required this.notes,
    required this.referencePath,
    required this.recordingPath,
    required this.offsetResult,
    required this.referenceDurationSec,
  });

  @override
  State<ReviewLastTakeV2Screen> createState() => _ReviewLastTakeV2ScreenState();
}

class _ReviewLastTakeV2ScreenState extends State<ReviewLastTakeV2Screen> {
  late PitchHighwayV2SessionController _controller;

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
    );
  }

  @override
  void dispose() {
    _controller.dispose();
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
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "REPLAY MODE (Audio Aligned)", 
                  style: TextStyle(color: Colors.white, fontSize: 20)
                ),
                const SizedBox(height: 20),
                Text(
                  "Offset: ${widget.offsetResult.offsetMs.toStringAsFixed(1)} ms", 
                  style: const TextStyle(color: Colors.grey)
                ),
                const SizedBox(height: 40),
                
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
                
                // Controls
                Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    children: [
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
                    ],
                  ),
                ),
                
                const Spacer(),
                
                Padding(
                  padding: const EdgeInsets.only(bottom: 48.0),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                      backgroundColor: Colors.white24
                    ),
                    onPressed: () {
                      // Navigate back to Home/Menu, assuming PlayerScreen was replaced or we pop recursively
                      Navigator.of(context).pop(); 
                    }, 
                    child: const Text("Done", style: TextStyle(fontSize: 18, color: Colors.white))
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
