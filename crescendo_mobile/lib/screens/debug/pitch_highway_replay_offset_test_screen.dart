import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../audio/wav_util.dart';

import '../../services/pitch_highway_session_controller.dart';
import '../../services/recording_service.dart';
import '../../models/reference_note.dart';
import '../../models/pitch_frame.dart';

class PitchHighwayReplayOffsetTestScreen extends StatefulWidget {
  const PitchHighwayReplayOffsetTestScreen({super.key});

  @override
  State<PitchHighwayReplayOffsetTestScreen> createState() => _PitchState();
}

class _PitchState extends State<PitchHighwayReplayOffsetTestScreen> {
  late PitchHighwaySessionController _controller;
  
  // Conf
  static const double _refDurationSec = 5.5;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    // 1. Create dummy notes
    final notes = [
      ReferenceNote(startSec: 1.0, endSec: 2.0, midi: 60),
      ReferenceNote(startSec: 2.5, endSec: 3.5, midi: 64),
      ReferenceNote(startSec: 4.0, endSec: 5.0, midi: 67),
    ];

    _controller = PitchHighwaySessionController(
      notes: notes,
      referenceDurationSec: _refDurationSec,
      ensureReferenceWav: _ensureReferenceWav,
      ensureRecordingPath: () async {
         final dir = await getTemporaryDirectory();
         return '${dir.path}/rec_offset_test.wav';
      },
      recorderFactory: () => RecordingService(owner: 'offset_test', bufferSize: 1024),
    );

    await _controller.prepare();
  }

  Future<String> _ensureReferenceWav() async {
     final dir = await getTemporaryDirectory();
     final path = '${dir.path}/ref_test_chirp.wav';
     return _generateTestWav(path);
  }

  Future<String> _generateTestWav(String path) async {
     // Generate 16-bit PCM: 48kHz, 6s.
     // Chirp at 0.2s. Tone at 1.0s.
     final sr = 48000;
     final len = (_refDurationSec * sr).toInt();
     final bytes = Int16List(len);
     
     for (int i=0; i<len; i++) {
        double t = i / sr;
        double val = 0;
        
        // Impulse/Chirp at 0.1s
        if (t >= 0.1 && t < 0.11) { // 10ms click
           val = 0.8 * math.sin(2 * math.pi * 1000 * t); // simple beep
        }
        
        // Notes
        if (t >= 1.0 && t < 2.0) val = 0.5 * math.sin(2 * math.pi * 261.63 * t); // C4
        if (t >= 2.5 && t < 3.5) val = 0.5 * math.sin(2 * math.pi * 329.63 * t); // E4
        if (t >= 4.0 && t < 5.0) val = 0.5 * math.sin(2 * math.pi * 392.00 * t); // G4
        
        bytes[i] = (val * 32767).toInt();
     }
     
     return WavUtil.writePcm16MonoWav(path, bytes, sr);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
       // Should not happen if initState synchronous part runs first, but late init can be risky if accessed before assignment. 
       // _controller is assigned synchronously in _initController (only .prepare() is async). 
       // So this is safe.
       return const SizedBox(); 
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Offset Alignment Test (V2 Controller)')),
      body: ValueListenableBuilder<PitchHighwaySessionState>(
        valueListenable: _controller.state,
        builder: (context, state, _) {
          return Column(
            children: [
              // Header Status
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.grey[200],
                child: Row(
                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                   children: [
                     Text('Phase: ${state.phase.name.toUpperCase()}'),
                     if (state.phase == PitchHighwaySessionPhase.recording) 
                       Text('${state.recordVisualTimeSec.toStringAsFixed(1)} / $_refDurationSec s'),
                   ],
                ),
              ),
              
              // Main Content
              Expanded(
                child: Builder(builder: (context) {
                   switch (state.phase) {
                     case PitchHighwaySessionPhase.recording:
                       return _buildRecordingUI(state);
                     case PitchHighwaySessionPhase.replay:
                       return _buildReplayUI(state);
                     case PitchHighwaySessionPhase.processing:
                       return const Center(child: CircularProgressIndicator());
                     case PitchHighwaySessionPhase.idle:
                     default:
                       return _buildIdleUI(state);
                   }
                }),
              ),
            ],
          );
        },
      ),
    );
  }
  
  Widget _buildIdleUI(PitchHighwaySessionState state) {
    return Center(
      child: ElevatedButton.icon(
        icon: const Icon(Icons.mic, size: 32),
        label: const Text('Start Test\n(Headphones Recommended!)', textAlign: TextAlign.center),
        style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(24)),
        onPressed: state.referencePath == null ? null : () => _controller.start(),
      ),
    );
  }
  
  Widget _buildRecordingUI(PitchHighwaySessionState state) {
    return Stack(
      children: [
        Positioned.fill(child: Container(color: Colors.black87)),
        CustomPaint(
          size: Size.infinite,
          painter: SimpleNotesPainter(state.notes, state.recordVisualTimeSec, 48, 72),
        ),
        CustomPaint(
           size: Size.infinite,
           painter: SimplePitchPainter(state.capturedFrames, state.recordVisualTimeSec, 48, 72),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Text("Sing along with the tones!", style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
          ),
        )
      ],
    );
  }
  
  Widget _buildReplayUI(PitchHighwaySessionState state) {
    final offsetResult = state.offsetResult;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
             // Results
             if (offsetResult != null)
             Card(
               child: Padding(
                 padding: const EdgeInsets.all(16.0),
                 child: Column(
                   children: [
                     const Text("Alignment Result", style: TextStyle(fontWeight: FontWeight.bold)),
                     const Divider(),
                     Text("Offset: ${offsetResult.offsetSamples} samples"),
                     Text("Time: ${offsetResult.offsetMs.toStringAsFixed(2)} ms"),
                     Text("Confidence: ${offsetResult.confidence.toStringAsFixed(2)}"),
                     Text("Method: ${offsetResult.method}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                   ],
                 ),
               ),
             ),
             
             const SizedBox(height: 24),
             
             // Visualizer
             SizedBox(
               height: 200,
               child: ClipRect(
                 child: Stack(
                  children: [
                    Positioned.fill(child: Container(color: Colors.black)),
                    CustomPaint(
                      size: Size.infinite,
                      painter: SimpleNotesPainter(state.notes, state.replayVisualTimeSec, 48, 72),
                    ),
                    CustomPaint(
                      size: Size.infinite,
                      painter: SimplePitchPainter(
                        state.capturedFrames, 
                        state.replayVisualTimeSec, 
                        48, 
                        72,
                        timeOffsetSec: state.applyOffset ? -(offsetResult?.offsetMs ?? 0) / 1000.0 : 0
                      ),
                    ),
                  ],
                 ),
               ),
             ),
              
             const SizedBox(height: 24),
              
             // Controls
             SwitchListTile(
                title: const Text("Apply Offset Correction"),
                value: state.applyOffset,
                onChanged: _controller.setApplyOffset,
             ),
             
             const Text("Reference Volume"),
             Slider(value: state.refVolume, onChanged: _controller.setRefVolume),
             
             const Text("Recording Volume"),
             Slider(value: state.recVolume, onChanged: _controller.setRecVolume),
             
             const SizedBox(height: 20),
             
             Row(
               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
               children: [
                 ElevatedButton.icon(
                   style: ElevatedButton.styleFrom(
                     padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                     backgroundColor: state.isPlayingReplay ? Colors.red : Colors.green,
                   ),
                   icon: Icon(state.isPlayingReplay ? Icons.stop : Icons.play_arrow),
                   label: Text(state.isPlayingReplay ? "STOP" : "PLAY ALIGNED"),
                   onPressed: () => _controller.toggleReplay(),
                 ),
                 
                 OutlinedButton(
                   onPressed: () async {
                      await _controller.stop(); 
                      if (mounted) {
                         // Prepare again to restart
                         _controller.prepare();
                      }
                   },
                   child: const Text("Done"),
                 )
               ],
             ),
             const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ---- Helpers (Preserved) ----

class SimpleNotesPainter extends CustomPainter {
  final List<ReferenceNote> notes;
  final double now;
  final int minMidi;
  final int maxMidi;
  
  SimpleNotesPainter(this.notes, this.now, this.minMidi, this.maxMidi);
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.blue.withValues(alpha: 0.5);
    final width = size.width;
    final height = size.height;
    
    double tToX(double t) => (t / 6.0) * width;
    double mToY(int m) => height - ((m - minMidi) / (maxMidi - minMidi)) * height;
    
    // Draw Notes
    for (var n in notes) {
      final rect = Rect.fromLTRB(
        tToX(n.startSec), 
        mToY(n.midi) - 10, 
        tToX(n.endSec), 
        mToY(n.midi) + 10
      );
      canvas.drawRect(rect, paint);
    }
    
    // Cursor
    final cx = tToX(now);
    canvas.drawLine(Offset(cx, 0), Offset(cx, height), Paint()..color = Colors.white..strokeWidth=2);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class SimplePitchPainter extends CustomPainter {
  final List<PitchFrame> frames;
  final double now; // unused if static
  final int minMidi;
  final int maxMidi;
  final double timeOffsetSec;

  SimplePitchPainter(this.frames, this.now, this.minMidi, this.maxMidi, {this.timeOffsetSec = 0.0});
  
  @override
  void paint(Canvas canvas, Size size) {
    if (frames.isEmpty) return;
    
    final paint = Paint()
      ..color = Colors.yellow
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final width = size.width;
    final height = size.height;

    double tToX(double t) => (t / 6.0) * width;
    double mToY(double m) => height - ((m - minMidi) / (maxMidi - minMidi)) * height;

    final path = Path();
    bool first = true;
    
    for (var f in frames) {
       if (f.midi == null) continue;
       final x = tToX(f.time + timeOffsetSec); 
       final y = mToY(f.midi!);
       
       if (first) {
         path.moveTo(x, y);
         first = false;
       } else {
         path.lineTo(x, y);
       }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
