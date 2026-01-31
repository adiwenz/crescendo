import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crescendo_mobile/transport_clock.dart';
import 'package:audioplayers/audioplayers.dart';

class TransportClockTestScreen extends StatefulWidget {
  const TransportClockTestScreen({super.key});

  @override
  State<TransportClockTestScreen> createState() =>
      _TransportClockTestScreenState();
}

class _TransportClockTestScreenState extends State<TransportClockTestScreen>
    with SingleTickerProviderStateMixin {
  final TransportClock _clock = TransportClock();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _initialized = false;
  bool _recording = false;
  bool _playingResult = false;

  double _sampleRate = 0.0;
  int? _playbackStartSample;
  int? _recordStartSample;

  String? _referencePath;
  String? _recordingPath;
  String? _goodMixPath;
  String? _badMixPath;

  int _offsetSamples = 0;

  Timer? _recordTimer;

  // Animation for playback visualization
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(seconds: 5));
    _animController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _animController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await _clock.ensureStarted();
      final sr = await _clock.getSampleRate();

      // Load asset to temp file
      final tempDir = await getTemporaryDirectory();
      final refFile = File('${tempDir.path}/reference.wav');
      // If asset doesn't exist, this will crash. User warned in plan.
      // But let's try-catch carefully.
      try {
        final byteData = await rootBundle.load('assets/audio/reference.wav');
        await refFile.writeAsBytes(byteData.buffer.asUint8List());
        _referencePath = refFile.path;
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error loading asset: $e")));
        return;
      }

      setState(() {
        _sampleRate = sr;
        _initialized = true;
      });
    } catch (e) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Init error: $e")));
    }
  }

  Future<void> _playAndRecord() async {
    if (_referencePath == null) return;

    try {
      // 1. Start recording
      final dir = await getTemporaryDirectory();
      _recordingPath = await _clock.startRecording(dirPath: dir.path);

      // 2. Play reference immediately
      await _clock.startPlayback(path: _referencePath!);

      setState(() {
        _recording = true;
        _playbackStartSample = null;
        _recordStartSample = null;
      });

      // 3. Auto-stop after 5s
      _recordTimer?.cancel();
      _recordTimer = Timer(const Duration(seconds: 5), () {
        _stopRecording();
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _stopRecording() async {
    await _clock.stopRecording();
    await _clock.stopAll(); // Stop playback too

    final pStart = await _clock.getPlaybackStartSampleTime();
    final rStart = await _clock.getRecordStartSampleTime();

    setState(() {
      _recording = false;
      _playbackStartSample = pStart;
      _recordStartSample = rStart;
    });
  }

  void _computeOffset() {
    if (_playbackStartSample == null || _recordStartSample == null) return;
    final diff = _recordStartSample! - _playbackStartSample!;
    setState(() {
      _offsetSamples = diff;
    });
  }

  Future<void> _createMix(bool useOffset) async {
    if (_referencePath == null || _recordingPath == null) return;

    final dir = await getTemporaryDirectory();
    final name = useOffset ? "good_mix.wav" : "bad_mix.wav";
    final outPath = "${dir.path}/$name";

    // If "Good", we want to shift the vocal such that it aligns.
    // recordStart was later than playbackStart by _offsetSamples.
    // That means the first sample of recording captures (playbackStart + offset).
    // So relative to playback start (t=0), the recording starts at t = offset.
    // So we pass offsetSamples = _offsetSamples.
    final offset = useOffset ? _offsetSamples : 0;

    try {
      final res = await _clock.mixWithOffset(
        referencePath: _referencePath!,
        vocalPath: _recordingPath!,
        vocalOffsetSamples: offset,
        outputPath: outPath,
      );

      setState(() {
        if (useOffset) {
          _goodMixPath = res;
        } else {
          _badMixPath = res;
        }
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Mix Error: $e")));
    }
  }

  Future<void> _playMix(String? path) async {
    if (path == null) return;
    await _audioPlayer.play(DeviceFileSource(path));
    
    // Simulate timeline playback
    _animController.reset();
    _animController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Transport Clock Test")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (!_initialized)
              ElevatedButton(
                  onPressed: _initialize, child: const Text("Initialize Engine"))
            else ...[
              Text("Sample Rate: $_sampleRate"),
              const SizedBox(height: 8),
              Text("Ref Path: .../${_referencePath?.split('/').last ?? 'None'}"),
              const SizedBox(height: 20),
              
              if (_recording)
                const Text("RECORDING... (5s)", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
              else
                ElevatedButton(
                  onPressed: _playAndRecord,
                  child: const Text("Play Reference + Record Mic (5s)"),
                ),
              
              const SizedBox(height: 20),
              Text("Playback Start: $_playbackStartSample"),
              Text("Record Start: $_recordStartSample"),
              Text("Offset (Samples): $_offsetSamples"),
              Text("Offset (ms): ${(_offsetSamples / (_sampleRate == 0 ? 48000 : _sampleRate) * 1000).toStringAsFixed(2)} ms"),
              
              const SizedBox(height: 10),
              ElevatedButton(onPressed: _computeOffset, child: const Text("Compute Offset")),
              
              const Divider(),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(onPressed: () => _createMix(true), child: const Text("Create GOOD Mix")),
                  ElevatedButton(onPressed: () => _createMix(false), child: const Text("Create BAD Mix")),
                ],
              ),
               const SizedBox(height: 10),
               Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(onPressed: _goodMixPath == null ? null : () => _playMix(_goodMixPath), child: const Text("Play GOOD")),
                  ElevatedButton(onPressed: _badMixPath == null ? null : () => _playMix(_badMixPath), child: const Text("Play BAD")),
                ],
              ),

              const Divider(),
              const Text("Visualization", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              _buildTimeline(),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    // Total duration ~5s for visualization
    const totalWidth = 300.0;
    
    // Calculate relative offset position
    // If offset is 5000 samples @ 48k, that's ~0.1s.
    double offsetRatio = 0.0;
    if (_sampleRate > 0) {
      offsetRatio = (_offsetSamples / _sampleRate) / 5.0; // ratio of 5s
    }
    
    final progress = _animController.value;

    return Container(
      height: 150,
      width: totalWidth,
      color: Colors.grey[200],
      child: Stack(
        children: [
          // Reference Track (Top)
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            height: 40,
            child: Container(color: Colors.blue[100], child: const Center(child: Text("Reference"))),
          ),
          
          // Vocal Track (Bottom)
          Positioned(
            top: 80,
            left: totalWidth * offsetRatio, // Offset visually
            right: 0, 
            height: 40,
            child: Container(color: Colors.green[100], child: const Center(child: Text("Vocal (Recorded)"))),
          ),
          
          // Playhead
          Positioned(
             left: totalWidth * progress, // moving
             top: 0,
             bottom: 0,
             child: Container(width: 2, color: Colors.red),
          )
        ],
      ),
    );
  }
}
