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
  String? _recordingPath; // Unique per run
  String? _referencePath; // Stable reference
  int _vocOffset = 0;
  bool _muteRef = false;
  bool _muteVoc = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    super.initState();
    _ensureCleanReference();
  }
  
  Future<void> _ensureCleanReference() async {
    // Determine path
    String playbackPath = "assets/audio/backing.wav"; 
    if (Platform.isIOS || Platform.isAndroid) {
         final dir = await getTemporaryDirectory();
         final file = File('${dir.path}/backing_ref.wav');
         // Always overwrite to ensure clean reference (not a previous mix)
         final data = await rootBundle.load("assets/audio/backing.wav");
         await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
         
         // print("Restored clean reference to: ${file.path}");
         playbackPath = file.path;
    }
    _referencePath = playbackPath;
    
    // Viz loading omitted for brevity as it's just visual
    if (await File(playbackPath).exists() && _referenceSamples == null) {
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
      
      // Ensure clean reference before recording
      await _ensureCleanReference();

      print("[Record] referencePath=$_referencePath recordingPath=$_recordingPath");
      
      // Start DUPLEX (Record)
      final success = await OneClockAudio.start(OneClockStartConfig(
        playbackWavAssetOrPath: _referencePath ?? "assets/audio/backing.wav",
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

    // 1. Pad recording with silence to align with 0
    int offsetFrames = 0;
    if (_captures.isNotEmpty) {
        offsetFrames = _captures.first.outputFramePos;
        if (offsetFrames < 0) offsetFrames = 0;
    }
    
    // Create padded buffer
    final rawRecorded = Uint8List.fromList(_recordedBytes).buffer.asInt16List();
    final totalSamples = offsetFrames + rawRecorded.length;
    final paddedBuffer = Int16List(totalSamples);
    
    // Fill silence (0) for offset loops implicitly 0, but Explicit copy for safety
    // Dart Int16List initiates to 0, so just copy recorded data after offset
    for (int i = 0; i < rawRecorded.length; i++) {
        paddedBuffer[offsetFrames + i] = rawRecorded[i];
    }
    
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/vocal_$timestamp.wav');
    
    await WavUtil.writePcm16MonoWav(file.path, paddedBuffer, 48000);
    _recordingPath = file.path;
    print("[DuplexUI] Stop: padded with $offsetFrames frames of silence. Total samples=$totalSamples.");
    print("Saved recording to: $_recordingPath");

    // 2. Force offset to 0 since we baked it in
    _vocOffset = 0;

    setState(() {
        _running = false;
        _status = "Stopped. Ready to Play.";
    });
    
    // 3. Pre-load Native Engine for Playback
    await _setupNativeEngine();
  }
  
  Future<void> _setupNativeEngine() async {
      if (_referencePath == null || _recordingPath == null) return;
      
      await OneClockAudio.loadReference(_referencePath!);
      await OneClockAudio.loadVocal(_recordingPath!);
      await _updateNativeParams();
  }
  
  Future<void> _updateNativeParams() async {
      await OneClockAudio.setVocalOffset(_vocOffset);
      await OneClockAudio.setTrackGains(
          ref: _muteRef ? 0.0 : 1.0, 
          voc: _muteVoc ? 0.0 : 4.0 // Default 4x boost for voc
      );
  }

  Future<void> _playBoth() async {
      if (_isPlaying) { 
        await OneClockAudio.stop();
        setState(() => _isPlaying = false);
        return; 
      }
      
      // Respect current UI mute toggles
      print("[DuplexUI] Starting Playback: muteRef=$_muteRef muteVoc=$_muteVoc offset=$_vocOffset");
      // Explicitly update params before start to ensure sync
      await _updateNativeParams(); 
      
      await _startPlayNative();
  }
  
  // Helpers (Unused by main UI button now, but kept for logic if needed)
  Future<void> _playRefOnly() async {
      if (_isPlaying) { _cancelPlay(); return; }
      setState(() { _muteRef = false; _muteVoc = true; });
      await _startPlayNative();
  }
  
  Future<void> _playRecOnly() async {
      if (_isPlaying) { _cancelPlay(); return; }
      setState(() { _muteRef = true; _muteVoc = false; });
      await _startPlayNative();
  }

  Future<void> _startPlayNative() async {
      await _setupNativeEngine(); // Ensure paths loaded
      await _updateNativeParams(); 
      final ok = await OneClockAudio.startPlaybackTwoTrack();
      if (ok) setState(() => _isPlaying = true);
      else setState(() => _status = "Playback Start Failed");
  }

  Future<void> _cancelPlay() async {
      await OneClockAudio.stop();
      setState(() => _isPlaying = false);
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
                   ]
                 ),
                 const SizedBox(height: 10),
                 if (_recordingPath != null) ...[
                      // Playback Controls
                      ElevatedButton(
                          onPressed: _playBoth, 
                          child: Text(_isPlaying ? "STOP PLAYBACK" : "PLAY (Mute to isolate)")
                      ),
                      
                      const SizedBox(height: 10),
                      
                      // Mute Toggles
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

                      const SizedBox(height: 10),
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
