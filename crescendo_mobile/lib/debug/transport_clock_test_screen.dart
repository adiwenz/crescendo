import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:one_clock_audio/one_clock_audio.dart';

class TransportClockTestScreen extends StatefulWidget {
  const TransportClockTestScreen({super.key});

  @override
  State<TransportClockTestScreen> createState() =>
      _TransportClockTestScreenState();
}

class _TransportClockTestScreenState extends State<TransportClockTestScreen>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _initialized = false;
  bool _recording = false;

  double _sampleRate = 0.0;
  int? _playbackStartSample;
  int? _recordStartSample;

  String? _referencePath;
  String? _recordingPath;
  String? _goodMixPath;
  String? _badMixPath;

  int _offsetSamples = 0;

  bool _muteRef = false;
  bool _muteVoc = false;
  bool _playingWithOneClock = false;

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
      await OneClockAudio.ensureStarted();
      final sr = await OneClockAudio.getSampleRate();

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
      if (Platform.isIOS && _playingWithOneClock) {
        await OneClockAudio.stop();
        setState(() => _playingWithOneClock = false);
      }
      // 1. Start recording (build output path)
      final dir = await getTemporaryDirectory();
      final outputPath = '${dir.path}/crescendo_recording_${DateTime.now().millisecondsSinceEpoch}.wav';
      _recordingPath = await OneClockAudio.startRecording(outputPath: outputPath);

      // 2. Play reference immediately
      await OneClockAudio.startPlayback(referencePath: _referencePath!, gain: 1.0);

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
    await OneClockAudio.stopRecording();
    await OneClockAudio.stopAll(); // Stop playback too

    final pStart = await OneClockAudio.getPlaybackStartSampleTime();
    final rStart = await OneClockAudio.getRecordStartSampleTime();

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
      final res = await OneClockAudio.mixWithOffset(
        referencePath: _referencePath!,
        vocalPath: _recordingPath!,
        outPath: outPath,
        vocalOffsetSamples: offset,
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
    if (_referencePath == null || _recordingPath == null) return;

    // On iOS use one_clock_audio for two-track playback so mute ref/voc works
    if (Platform.isIOS) {
      if (_playingWithOneClock) await OneClockAudio.stop();
      setState(() => _playingWithOneClock = true);
      await OneClockAudio.loadReference(_referencePath!);
      await OneClockAudio.loadVocal(_recordingPath!);
      final useGoodOffset = path == _goodMixPath;
      await OneClockAudio.setVocalOffset(useGoodOffset ? _offsetSamples : 0);
      await OneClockAudio.setTrackGains(
        ref: _muteRef ? 0.0 : 1.0,
        voc: _muteVoc ? 0.0 : 1.0,
      );
      final ok = await OneClockAudio.startPlaybackTwoTrack();
      if (!ok && mounted) {
        setState(() => _playingWithOneClock = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Two-track playback failed")),
        );
        return;
      }
    } else {
      await _audioPlayer.play(DeviceFileSource(path));
    }

    // Simulate timeline playback
    _animController.reset();
    _animController.forward();
  }

  Future<void> _updateTwoTrackGains() async {
    if (!_playingWithOneClock) return;
    await OneClockAudio.setTrackGains(
      ref: _muteRef ? 0.0 : 1.0,
      voc: _muteVoc ? 0.0 : 1.0,
    );
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
              // iOS: mute ref/voc during two-track playback
              if (Platform.isIOS && (_goodMixPath != null || _badMixPath != null)) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _MuteButton(
                      label: 'Ref',
                      muted: _muteRef,
                      onPressed: () {
                        setState(() => _muteRef = !_muteRef);
                        _updateTwoTrackGains();
                      },
                    ),
                    const SizedBox(width: 16),
                    _MuteButton(
                      label: 'Voc',
                      muted: _muteVoc,
                      onPressed: () {
                        setState(() => _muteVoc = !_muteVoc);
                        _updateTwoTrackGains();
                      },
                    ),
                  ],
                ),
              ],

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

/// Mute button for ref or vocal: icon + label, toggles muted state.
class _MuteButton extends StatelessWidget {
  final String label;
  final bool muted;
  final VoidCallback onPressed;

  const _MuteButton({
    required this.label,
    required this.muted,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: muted ? Theme.of(context).colorScheme.primaryContainer : null,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                muted ? Icons.volume_off : Icons.volume_up,
                size: 22,
                color: muted ? Theme.of(context).colorScheme.onPrimaryContainer : null,
              ),
              const SizedBox(width: 8),
              Text(
                'Mute $label',
                style: TextStyle(
                  fontWeight: muted ? FontWeight.bold : FontWeight.normal,
                  color: muted ? Theme.of(context).colorScheme.onPrimaryContainer : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
