import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:one_clock_audio/one_clock_audio.dart'; // Unified plugin
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:permission_handler/permission_handler.dart';
import '../audio/wav_util.dart';

class DuplexAudioTestScreen extends StatefulWidget {
  const DuplexAudioTestScreen({super.key});

  @override
  State<DuplexAudioTestScreen> createState() => _DuplexAudioTestScreenState();
}

class _DuplexAudioTestScreenState extends State<DuplexAudioTestScreen> {
  String _status = "Ready";
  bool _running = false;
  
  // Recording Data
  final List<OneClockCapture> _captures = [];
  final List<int> _recordedBytes = [];
  
  // Visualization
  Float32List? _referenceSamples;
  final List<double> _captureVisPoints = [];
  int _visDownsample = 100; // rough visual downsampling
  
  OneClockCapture? _lastCapture;
  StreamSubscription? _sub;

  // New Playback State
  String? _vocalPath; 
  String? _refPathCache; // path to reference if loaded from assets
  int _vocOffset = 0;
  bool _muteRef = false;
  bool _muteVoc = false;
  bool _isPlaying = false; // Track if playback is active (simple toggle)

  @override
  void initState() {
    super.initState();
    _loadReference();
  }
  
  Future<void> _loadReference() async {
    // Determine path
    String playbackPath = "assets/audio/backing.wav"; 
    if (Platform.isIOS || Platform.isAndroid) {
         final dir = await getTemporaryDirectory();
         final file = File('${dir.path}/backing_ref.wav');
         // Always overwrite to ensure clean reference (not a previous mix)
         final data = await rootBundle.load("assets/audio/backing.wav");
         await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
         
         print("Restored clean reference to: ${file.path}");
         playbackPath = file.path;
    }
    _refPathCache = playbackPath;
    
    // Load for viz
    // Simplified viz load for brevity:
    if (await File(playbackPath).exists()) {
        final bytes = await File(playbackPath).readAsBytes();
        if (bytes.length > 44) {
             final ints = bytes.buffer.asInt16List(44);
             _referenceSamples = Float32List(ints.length);
             for(int i=0; i<ints.length; i++) _referenceSamples![i] = ints[i] / 32768.0;
        }
    }
  }

  Future<void> _start() async {
    if (_running) return;
    
    // Stop playback if running
    if (_isPlaying) {
        await OneClockAudio.stop();
        setState(() => _isPlaying = false);
    }

    try {
      setState(() {
        _status = "Starting Recording...";
        _eventCount = 0;
        _captures.clear();
        _captureVisPoints.clear();
        _recordedBytes.clear();
      });

      _sub = OneClockAudio.captureStream.listen((event) {
        if (!mounted) return;
        _captures.add(event); 
        _recordedBytes.addAll(event.pcm16); // Accumulate Raw

        // Vis logic 
        final pcm = event.pcm16.buffer.asInt16List();
         for (int i = 0; i < pcm.length; i += _visDownsample) {
            _captureVisPoints.add(pcm[i] / 32768.0);
         }

        setState(() {
          _eventCount++;
          _lastCapture = event;
          _status = "Recording: $_eventCount callbacks";
        });
      });
      
      // Start DUPLEX (Record)
      final success = await OneClockAudio.start(OneClockStartConfig(
        playbackWavAssetOrPath: _refPathCache ?? "assets/audio/backing.wav",
        sampleRate: 48000,
        channels: 1,
      ));

      if (!success) {
        setState(() => _status = "Error: Engine start failed");
      } else {
        setState(() => _running = true);
      }
    } catch (e) {
      print("Error starting: $e");
    }
  }

  int _eventCount = 0;

  Future<void> _stop() async {
    if (!_running) return;
    await OneClockAudio.stop();
    _sub?.cancel();
    _sub = null;

    setState(() => _status = "Saving...");

    // 1. Save Raw Vocal
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/vocal_raw.wav');
    
    // Accumulate raw bytes
    final rawInt16 = Uint8List.fromList(_recordedBytes).buffer.asInt16List();
    await WavUtil.writePcm16MonoWav(file.path, rawInt16, 48000);
    _vocalPath = file.path;

    // 2. Determine initial offset (from first capture)
    if (_captures.isNotEmpty) {
        _vocOffset = _captures.first.outputFramePos;
    } else {
        _vocOffset = 0;
    }

    setState(() {
        _running = false;
        _status = "Stopped. Ready to Play.";
    });
    
    // 3. Pre-load Native Engine for Playback
    await _setupNativeEngine();
  }
  
  Future<void> _setupNativeEngine() async {
      if (_refPathCache == null || _vocalPath == null) return;
      
      await OneClockAudio.loadReference(_refPathCache!);
      await OneClockAudio.loadVocal(_vocalPath!);
      await _updateNativeParams();
  }
  
  Future<void> _updateNativeParams() async {
      await OneClockAudio.setVocalOffset(_vocOffset);
      await OneClockAudio.setTrackGains(
          ref: _muteRef ? 0.0 : 1.0, 
          voc: _muteVoc ? 0.0 : 4.0 // Default 4x boost for voc
      );
  }

  Future<void> _togglePlayback() async {
      if (_isPlaying) {
          await OneClockAudio.stop();
          setState(() => _isPlaying = false);
      } else {
          // ensure params are fresh
          await _updateNativeParams(); 
          final ok = await OneClockAudio.startPlaybackTwoTrack();
          if (ok) {
              setState(() => _isPlaying = true);
          } else {
              setState(() => _status = "Playback Start Failed");
          }
      }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Native Two-Track Test")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
             Text(_status),
             const SizedBox(height: 10),
             // Viz Area
             Expanded(
               child: Container(
                 decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
                 child: ClipRect(
                   child: CustomPaint(
                     painter: _WaveformPainter(
                       reference: _referenceSamples,
                       capture: _captureVisPoints,
                       downsample: _visDownsample,
                     ),
                     size: Size.infinite,
                   ),
                 ),
               ),
             ),
             const SizedBox(height: 20),
             // Controls
             if (!_running) ...[
                 Row(
                   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                   children: [
                       ElevatedButton(
                           onPressed: _start, 
                           style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                           child: const Text("RECORD")
                       ),
                       ElevatedButton(
                           onPressed: _vocalPath == null ? null : _togglePlayback, 
                           child: Text(_isPlaying ? "STOP PLAY" : "PLAY BOTH")
                       ),
                   ]
                 ),
                 const SizedBox(height: 10),
                 if (_vocalPath != null) ...[
                     Row(children: [
                         const Text("Offset: "),
                         IconButton(icon: const Icon(Icons.remove), onPressed: () {
                             setState(() => _vocOffset -= 100);
                             _updateNativeParams();
                         }),
                         Text("$_vocOffset f"),
                         IconButton(icon: const Icon(Icons.add), onPressed: () {
                             setState(() => _vocOffset += 100);
                             _updateNativeParams();
                         }),
                     ]),
                     Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                         FilterChip(label: const Text("Mute Ref"), selected: _muteRef, onSelected: (v) {
                             setState(() => _muteRef = v);
                             _updateNativeParams();
                         }),
                         FilterChip(label: const Text("Mute Voc"), selected: _muteVoc, onSelected: (v) {
                             setState(() => _muteVoc = v);
                             _updateNativeParams();
                         }),
                     ]),
                 ]
             ] else ...[
                 ElevatedButton(onPressed: _stop, child: const Text("STOP RECORDING"))
             ]
          ],
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final Float32List? reference;
  final List<double> capture;
  final int downsample;
  
  _WaveformPainter({required this.reference, required this.capture, required this.downsample});
  
  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    // Draw Reference (Top half, blue)
    if (reference != null) {
      final paint = Paint()..color = Colors.blue.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 1;
      final path = Path();
      
      for (int i = 0; i < reference!.length ~/ downsample; i++) {
        final x = i.toDouble();
        if (x > size.width) break;
        final val = reference![i * downsample];
        final y = midY - (size.height / 4) + (val * (size.height / 4));
        if (i == 0) path.moveTo(x, y);
        else path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    }
    
    // Draw Capture (Bottom half, red)
    if (capture.isNotEmpty) {
      final paint = Paint()..color = Colors.red.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 1;
      final path = Path();
       for (int i = 0; i < capture.length; i++) {
        final x = i.toDouble(); // Assuming same downsample rate implies alignment if start is aligned
        if (x > size.width) break;
        final val = capture[i];
         // Draw in bottom half
        final y = midY + (size.height / 4) + (val * (size.height / 4));
        if (i == 0) path.moveTo(x, y);
        else path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    }
    
    // Draw centerline
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), Paint()..color = Colors.black);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
