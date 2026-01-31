import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:crescendo_mobile/duplex_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart' show rootBundle;

class DuplexAudioTestScreen extends StatefulWidget {
  const DuplexAudioTestScreen({super.key});

  @override
  State<DuplexAudioTestScreen> createState() => _DuplexAudioTestScreenState();
}

class _DuplexAudioTestScreenState extends State<DuplexAudioTestScreen> {
  StreamSubscription? _sub;
  bool _running = false;
  int _eventCount = 0;
  DuplexCapture? _lastCapture;
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

      // Listen first
      _sub = DuplexAudio.stream.listen((event) {
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

      // Start engine
      await DuplexAudio.start(
        wavAssetPath: "assets/audio/backing.wav",
        sampleRate: 48000,
        channels: 1,
      );

      setState(() => _running = true);
    } catch (e) {
      setState(() => _status = "Error: $e");
    }
  }

  Future<void> _stop() async {
    if (!_running) return;
    await DuplexAudio.stop();
    _sub?.cancel();
    _sub = null;
    
    // Save file
    final path = await _saveWav(_recordedBytes);
    
    setState(() {
      _running = false;
      _status = "Stopped. Recorded ${_recordedBytes.length} bytes.";
      _recordedFilePath = path;
    });
  }
  
  Future<void> _playRecording() async {
    if (_recordedFilePath == null) return;
    await _player.play(DeviceFileSource(_recordedFilePath!));
  }
  
  Future<String> _saveWav(List<int> pcmData) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/android_duplex_rec.wav');
    
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
      appBar: AppBar(title: const Text("Android Duplex Test")),
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
      // Only draw what fits
      // Width = pixels. Each pixel = some number of samples?
      // Let's say we fit 5 seconds? 5s * 48000 = 240,000 samples.
      // If width is 400px, that's 600 samples per pixel.
      // Let's just map index to X simply: 1 point (downsampled) = 1 pixel width?
      // We have downsample=100. So 1 point = 100 samples.
      
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
