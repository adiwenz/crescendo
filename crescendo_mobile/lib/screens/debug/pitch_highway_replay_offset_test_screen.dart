import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import '../../audio/wav_util.dart';

import '../../services/audio_offset_estimator.dart';
import '../../services/audio_session_service.dart';
import '../../services/recording_service.dart';
import '../../services/audio_synth_service.dart';
import '../../services/reference_audio_generator.dart';
import '../../models/reference_note.dart';
import '../../models/pitch_frame.dart';
import '../../models/vocal_exercise.dart';
import '../../models/pitch_highway_difficulty.dart';
import '../../ui/widgets/pitch_highway_painter.dart';
import '../../utils/pitch_visual_state.dart';
import '../../utils/audio_constants.dart';

class PitchHighwayReplayOffsetTestScreen extends StatefulWidget {
  const PitchHighwayReplayOffsetTestScreen({super.key});

  @override
  State<PitchHighwayReplayOffsetTestScreen> createState() => _PitchState();
}

enum TestPhase { idle, recording, processing, replay }

class _PitchState extends State<PitchHighwayReplayOffsetTestScreen> with TickerProviderStateMixin {
  
  // State
  TestPhase _phase = TestPhase.idle;
  List<ReferenceNote> _notes = [];
  final List<PitchFrame> _capturedFrames = [];
  String? _refPath;
  String? _recPath;
  AudioOffsetResult? _offsetResult;
  double _refDurationSec = 6.0;

  // Audio / Services
  final AudioPlayer _refPlayer = AudioPlayer();
  final AudioPlayer _recPlayer = AudioPlayer();
  final AudioPlayer _refReplayPlayer = AudioPlayer(); // Separate player for replay
  RecordingService? _recorder;
  StreamSubscription<PitchFrame>? _pitchSub;
  
  // UI Replay Controls
  bool _isPlayingReplay = false;
  double _refVolume = 1.0;
  double _recVolume = 1.0;
  bool _applyOffset = true;

  // Canvas / Visuals
  Ticker? _ticker;
  Ticker? _replayTicker;
  double _visualTime = 0.0;
  double _replayVisualTime = 0.0;
  DateTime? _recordStartTime;
  DateTime? _replayStartTime;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (_phase == TestPhase.recording && _recordStartTime != null) {
        setState(() {
          _visualTime = DateTime.now().difference(_recordStartTime!).inMilliseconds / 1000.0;
        });
        
        // Auto-stop
        if (_visualTime >= _refDurationSec + 0.5) { // 0.5s trailing
          _stopRecording();
        }
      }
    });

    _replayTicker = createTicker((elapsed) {
       if (_phase == TestPhase.replay && _replayStartTime != null) {
          setState(() {
            _replayVisualTime = DateTime.now().difference(_replayStartTime!).inMilliseconds / 1000.0;
          });
       }
    });

    _prepareExercise();
    
    // Auto-reset UI when players finish
    _refReplayPlayer.onPlayerComplete.listen((_) {
      if (mounted && _isPlayingReplay) {
         setState(() {
           _isPlayingReplay = false;
           _replayTicker?.stop();
         });
         // Ensure both are stopped
         debugPrint("[Test] Replay finished (listener). Stopping players.");
         _recPlayer.stop(); 
         _refReplayPlayer.stop();
      }
    });
  }

  Future<void> _prepareExercise() async {
    // 1. Create dummy notes
    _notes = [
      ReferenceNote(startSec: 1.0, endSec: 2.0, midi: 60),
      ReferenceNote(startSec: 2.5, endSec: 3.5, midi: 64),
      ReferenceNote(startSec: 4.0, endSec: 5.0, midi: 67),
    ];
    _refDurationSec = 5.5;

    // 2. Generate reference WAV
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/ref_test_chirp.wav';
    
    _refPath = await _generateTestWav(path);
    setState(() {});
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

  Future<void> _startRecording() async {
    if (_refPath == null) return;
    
    // Audio Session
    await AudioSessionService.applyExerciseSession();
    
    final dir = await getTemporaryDirectory();
    _recPath = '${dir.path}/rec_offset_test.wav';
    
    _capturedFrames.clear();
    _visualTime = 0;

    _recorder = RecordingService(owner: 'offset_test', bufferSize: 1024);
    
    // Prepare Players
    await _refPlayer.setSourceDeviceFile(_refPath!);
    
    setState(() {
      _phase = TestPhase.recording;
    });

    // Start
    await _recorder!.start(owner: 'offset_test', mode: RecordingMode.take);
    _pitchSub = _recorder!.liveStream.listen((frame) {
      if (mounted) {
        // Just append, maybe throttle redraws if heavy
        setState(() {
           _capturedFrames.add(frame);
        });
      }
    });

    // Play Ref
    await _refPlayer.resume();
    
    _recordStartTime = DateTime.now();
    _ticker?.start();
  }

  Future<void> _stopRecording() async {
    _ticker?.stop();
    await _refPlayer.stop();
    await _recorder?.stop(customPath: _recPath); // explicit path
    _pitchSub?.cancel();
    
    setState(() {
      _phase = TestPhase.processing;
    });
    
    await _computeOffset();
  }

  Future<void> _computeOffset() async {
    if (_refPath == null || _recPath == null) return;
    
    final result = await AudioOffsetEstimator.estimateOffsetSamples(
      recordedPath: _recPath!, 
      referencePath: _refPath!,
      strategy: OffsetStrategy.auto
    );
    
    if (mounted) {
      setState(() {
        _offsetResult = result;
        _phase = TestPhase.replay;
      });
      
      // Switch to playback session for reliable output
      await AudioSessionService.applyReviewSession();
      
      // Prep replay players
      debugPrint('[Test] Preparing replay players...');
      debugPrint('[Test] Ref: $_refPath');
      debugPrint('[Test] Rec: $_recPath');
      
      if (_recPath != null) {
        final recFile = File(_recPath!);
        if (await recFile.exists()) {
           final len = await recFile.length();
           debugPrint('[Test] Rec file exists, size: $len bytes');
        } else {
           debugPrint('[Test] ERROR: Rec file does not exist at $_recPath');
        }
      }

      await _refReplayPlayer.setSourceDeviceFile(_refPath!);
      await _recPlayer.setSourceDeviceFile(_recPath!);
    }
  }

  Future<void> _toggleReplay() async {
    debugPrint("[Test] _toggleReplay called. isPlaying: $_isPlayingReplay");
    try {
      if (_isPlayingReplay) {
        debugPrint("[Test] Stopping replay...");
        _replayTicker?.stop();
        await _refReplayPlayer.stop();
        await _recPlayer.stop();
        setState(() => _isPlayingReplay = false);
        debugPrint("[Test] Replay stopped.");
      } else {
        // START ALIGNED
        
        // FORCE STOP / RESET state
        debugPrint("[Test] Resetting players (stop & seek 0)...");
        await _refReplayPlayer.stop();
        await _recPlayer.stop();
        
        final offsetMs = _applyOffset ? (_offsetResult?.offsetMs ?? 0) : 0;
        
        debugPrint("[Test] Starting replay. Offset: ${offsetMs}ms. Apply: $_applyOffset");
        
        debugPrint("[Test] Setting volumes...");
        await _refReplayPlayer.setVolume(_refVolume);
        await _recPlayer.setVolume(_recVolume);

        // Re-set sources to be absolutely sure
        debugPrint("[Test] Re-setting sources...");
        if (_refPath != null) await _refReplayPlayer.setSourceDeviceFile(_refPath!);
        if (_recPath != null) await _recPlayer.setSourceDeviceFile(_recPath!);
        
        debugPrint("[Test] Setting isPlayingReplay = true...");
        setState(() => _isPlayingReplay = true);
        
        if (offsetMs > 0) {
          // Ref is leading (happens first), Rec is lagging.
          debugPrint("[Test] Offset > 0. Playing Ref in ${offsetMs.toInt()}ms");
          
          debugPrint("[Test] Resuming RecPlayer (leading)...");
          await _recPlayer.resume(); 
          Future.delayed(Duration(milliseconds: offsetMs.toInt()), () async {
             // check if still playing (user might have stopped)
             if (_isPlayingReplay) {
               debugPrint("[Test] Playing Ref now (delayed)");
               await _refReplayPlayer.resume();
               _replayStartTime = DateTime.now();
               _replayTicker?.start();
             } else {
               debugPrint("[Test] Cancelled Ref start (stopped during delay)");
             }
          });
          
        } else {
          // Rec is leading. Delay Rec.
          debugPrint("[Test] Offset <= 0. Playing Ref NOW.");
          
          await _refReplayPlayer.resume();
          _replayStartTime = DateTime.now();
          _replayTicker?.start();
          
          final delay = offsetMs.abs().toInt();
          debugPrint("[Test] RecPlayer delayed by ${delay}ms");
          Future.delayed(Duration(milliseconds: delay), () async {
             if (_isPlayingReplay) {
               debugPrint("[Test] Playing Rec now (delayed)");
               await _recPlayer.resume();
             } else {
               debugPrint("[Test] Cancelled Rec start (stopped during delay)");
             }
          });
        }
      }
    } catch (e, stack) {
      debugPrint("[Test] ERROR in _toggleReplay: $e");
      debugPrint(stack.toString());
      // Force reset state on error
      setState(() => _isPlayingReplay = false);
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _replayTicker?.dispose();
    _refPlayer.dispose();
    _recPlayer.dispose();
    _refReplayPlayer.dispose();
    _recorder?.dispose();
    _pitchSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offset Alignment Test')),
      body: Column(
        children: [
          // Header Status
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[200],
            child: Row(
               mainAxisAlignment: MainAxisAlignment.spaceBetween,
               children: [
                 Text('Phase: ${_phase.name.toUpperCase()}'),
                 if (_phase == TestPhase.recording) 
                   Text('${_visualTime.toStringAsFixed(1)} / $_refDurationSec s'),
               ],
            ),
          ),
          
          // Main Content
          Expanded(
            child: _phase == TestPhase.recording 
             ? _buildRecordingUI()
             : _phase == TestPhase.replay 
               ? _buildReplayUI()
               : _phase == TestPhase.processing 
                 ? const Center(child: CircularProgressIndicator())
                 : _buildIdleUI(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildIdleUI() {
    return Center(
      child: ElevatedButton.icon(
        icon: const Icon(Icons.mic, size: 32),
        label: const Text('Start Test\n(Headphones Recommended!)', textAlign: TextAlign.center),
        style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(24)),
        onPressed: _refPath == null ? null : _startRecording,
      ),
    );
  }
  
  Widget _buildRecordingUI() {
    // We can use the real PitchHighwayPainter if we want, or a simplified visualizer
    // Let's try to reuse PitchHighwayPainter logic by wrapping it.
    // Assuming PitchHighwayPainter needs specific params.
    // For simplicity, let's just draw the live pitch trace.
    return Stack(
      children: [
        // Background
        Positioned.fill(child: Container(color: Colors.black87)),
        
        // Notes (Draw simplistic rectangles)
        CustomPaint(
          size: Size.infinite,
          painter: SimpleNotesPainter(_notes, _visualTime, 48, 72),
        ),
        
        // Pitch Trace
        CustomPaint(
           size: Size.infinite,
           painter: SimplePitchPainter(_capturedFrames, _visualTime, 48, 72),
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
  
  Widget _buildReplayUI() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
             // Results
             Card(
               child: Padding(
                 padding: const EdgeInsets.all(16.0),
                 child: Column(
                   children: [
                     const Text("Alignment Result", style: TextStyle(fontWeight: FontWeight.bold)),
                     const Divider(),
                     Text("Offset: ${_offsetResult?.offsetSamples} samples"),
                     Text("Time: ${_offsetResult?.offsetMs.toStringAsFixed(2)} ms"),
                     Text("Confidence: ${_offsetResult?.confidence.toStringAsFixed(2)}"),
                     Text("Method: ${_offsetResult?.method}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
                      painter: SimpleNotesPainter(_notes, _replayVisualTime, 48, 72),
                    ),
                    CustomPaint(
                      size: Size.infinite,
                      painter: SimplePitchPainter(
                        _capturedFrames, 
                        _replayVisualTime, 
                        48, 
                        72,
                        timeOffsetSec: _applyOffset ? -(_offsetResult?.offsetMs ?? 0) / 1000.0 : 0
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
                value: _applyOffset,
                onChanged: (v) => setState(() => _applyOffset = v),
             ),
             
             const Text("Reference Volume"),
             Slider(value: _refVolume, onChanged: (v) {
                setState(() => _refVolume = v);
                _refReplayPlayer.setVolume(v);
             }),
             
             const Text("Recording Volume"),
             Slider(value: _recVolume, onChanged: (v) {
                setState(() => _recVolume = v);
                _recPlayer.setVolume(v);
             }),
             
             const SizedBox(height: 20),
             
             Row(
               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
               children: [
                 ElevatedButton.icon(
                   style: ElevatedButton.styleFrom(
                     padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                     backgroundColor: _isPlayingReplay ? Colors.red : Colors.green,
                   ),
                   icon: Icon(_isPlayingReplay ? Icons.stop : Icons.play_arrow),
                   label: Text(_isPlayingReplay ? "STOP" : "PLAY ALIGNED"),
                   onPressed: _toggleReplay,
                 ),
                 
                 OutlinedButton(
                   onPressed: () => setState(() => _phase = TestPhase.idle),
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

// ---- Helpers ----

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
    // final timeWindow = 4.0; // show 4 seconds
    
    // transform: x is time (scrolling left), y is pitch
    // x=0 is 'now' at left? Or 'now' at 20%? 
    // classic highway: now is bottom/center. 
    // Scrolling left-to-right (sequencer view)?
    // Let's do sequencer view: x = (t - now) * pxPerSec + offset
    
    // Actually vertical highway is standard in this app.
    // Let's do vertical. y=time. x=pitch.
    // Time flows down? or up?
    // Let's stick to simple horizontal sequencer for debug:
    // Left=0s, Right=6s. static view. cursor moves.
    
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
       final x = tToX(f.time + timeOffsetSec); // PitchFrame time is relative to record start?
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
