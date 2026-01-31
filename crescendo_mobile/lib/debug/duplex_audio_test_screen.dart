import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:one_clock_audio/one_clock_audio.dart'; // Unified plugin
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:permission_handler/permission_handler.dart';

class DuplexAudioTestScreen extends StatefulWidget {
  const DuplexAudioTestScreen({super.key});

  @override
  State<DuplexAudioTestScreen> createState() => _DuplexAudioTestScreenState();
}

class _DuplexAudioTestScreenState extends State<DuplexAudioTestScreen> {
  StreamSubscription? _sub;
  bool _running = false;
  int _eventCount = 0;
  OneClockCapture? _lastCapture;
  String _status = "Ready";
  
  // Recording
  final List<int> _recordedBytes = [];
  String? _recordedFilePath;
  final AudioPlayer _player = AudioPlayer();
  
  // Visualization
  Float32List? _referenceSamples;
  final List<double> _captureVisPoints = []; // Normalized -1..1
  final int _visDownsample = 100; // Plot 1 point per N samples
  
  @override
  void initState() {
    super.initState();
    _loadReference();
  }

  Future<void> _loadReference() async {
    try {
      final bytes = await rootBundle.load('assets/audio/backing.wav');
      // Skip 44 bytes header for visualization (approx)
      final pcm16 = bytes.buffer.asInt16List(44); 
      // Convert to float for simpler plotting
      final floats = Float32List(pcm16.length);
      for (int i = 0; i < pcm16.length; i++) {
        floats[i] = pcm16[i] / 32768.0;
      }
      setState(() {
        _referenceSamples = floats;
      });
    } catch (e) {
      print("Error loading reference for vis: $e");
    }
  }

  @override
  void dispose() {
    _stop();
    _player.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_running) return;
    try {
      setState(() {
        _status = "Starting...";
        _eventCount = 0;
        _recordedBytes.clear();
        _captureVisPoints.clear();
        _recordedFilePath = null;
      });

      // Request permission
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        setState(() => _status = "Mic permission denied");
        return;
      }

      // Listen first
      _sub = OneClockAudio.captureStream.listen((event) {
        // Accumulate bytes for file saving
        _recordedBytes.addAll(event.pcm16);
        
        // Accumulate points for visualization (downsampled)
        final pcm = event.pcm16.buffer.asInt16List();
        for (int i = 0; i < pcm.length; i += _visDownsample) {
          _captureVisPoints.add(pcm[i] / 32768.0);
        }

        setState(() {
          _eventCount++;
          _lastCapture = event;
          _status = "Running: $_eventCount callbacks";
        });
      });

      // PREPARE ASSETS
      String playbackPath = "assets/audio/backing.wav"; // Default for Android
      
      if (Platform.isIOS) {
        // iOS needs a file path
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/backing_temp.wav');
        if (!await file.exists()) {
             final data = await rootBundle.load("assets/audio/backing.wav");
             await file.writeAsBytes(data.buffer.asUint8List());
        }
        playbackPath = file.path;
      }

      // Start engine
      await OneClockAudio.start(OneClockStartConfig(
        playbackWavAssetOrPath: playbackPath,
        sampleRate: 48000,
        channels: 1,
      ));

      setState(() => _running = true);
    } catch (e) {
      setState(() => _status = "Error: $e");
    }
  }

  Future<void> _stop() async {
    if (!_running) return;
    await OneClockAudio.stop();
    _sub?.cancel();
    _sub = null;
    
    // Save file with gain
    final boostedBytes = _applyDigitalGain(_recordedBytes, 4.0);
    final path = await _saveWav(boostedBytes);
    
    setState(() {
      _running = false;
      _status = "Stopped. Recorded ${_recordedBytes.length} bytes (Boosted 4x).";
      _recordedFilePath = path;
    });
  }

  List<int> _applyDigitalGain(List<int> input, double gain) {
    if (gain == 1.0) return input;
    final data = Uint8List.fromList(input); // Copy
    final view = ByteData.sublistView(data);
    
    for (int i = 0; i < data.length - 1; i += 2) {
      int sample = view.getInt16(i, Endian.little);
      int boosted = (sample * gain).round();
      if (boosted > 32767) boosted = 32767;
      if (boosted < -32768) boosted = -32768;
      view.setInt16(i, boosted, Endian.little);
    }
    return data.toList();
  }
  
  Future<void> _playRecording() async {
    if (_recordedFilePath == null) return;
    await _player.play(DeviceFileSource(_recordedFilePath!));
  }
  
  Future<String> _saveWav(List<int> pcmData) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/duplex_rec_${DateTime.now().millisecondsSinceEpoch}.wav');
    
    final int sampleRate = 48000;
    final int channels = 1;
    final int byteRate = sampleRate * channels * 2;
    final int dataSize = pcmData.length;
    final int totalSize = 36 + dataSize;
    
    final header = BytesBuilder();
    // RIFF
    header.add([0x52, 0x49, 0x46, 0x46]); 
    header.add(_int32(totalSize));
    // WAVE
    header.add([0x57, 0x41, 0x56, 0x45]);
    // fmt 
    header.add([0x66, 0x6d, 0x74, 0x20]);
    header.add(_int32(16)); // Chunk size
    header.add(_int16(1)); // PCM
    header.add(_int16(channels));
    header.add(_int32(sampleRate));
    header.add(_int32(byteRate));
    header.add(_int16(channels * 2)); // Block align
    header.add(_int16(16)); // Bits per sample
    // data
    header.add([0x64, 0x61, 0x74, 0x61]);
    header.add(_int32(dataSize));
    
    final allBytes = BytesBuilder();
    allBytes.add(header.toBytes());
    allBytes.add(pcmData);
    
    await file.writeAsBytes(allBytes.toBytes());
    return file.path;
  }
  
  List<int> _int32(int v) {
    final b = ByteData(4);
    b.setInt32(0, v, Endian.little);
    return b.buffer.asUint8List();
  }
  
  List<int> _int16(int v) {
    final b = ByteData(2);
    b.setInt16(0, v, Endian.little);
    return b.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Unified OneClock Test")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            if (_lastCapture != null) ...[
               Text("Frames: ${_lastCapture!.numFrames} | SR: ${_lastCapture!.sampleRate}"),
               Text("In: ${_lastCapture!.inputFramePos} | Out: ${_lastCapture!.outputFramePos}"),
            ],
            const SizedBox(height: 24),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
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
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _running ? _stop : _start,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _running ? Colors.red : Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(_running ? "STOP" : "RECORD (5s)"), // User can stop manually or we could add timer
                    ),
                  ),
                ),
                if (!_running && _recordedFilePath != null) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _playRecording,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text("REPLAY RECORDING"),
                      ),
                    ),
                  ),
                ]
              ],
            ),
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
