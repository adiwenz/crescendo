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
  StreamSubscription? _sub;
  bool _running = false;
  int _eventCount = 0;
  OneClockCapture? _lastCapture;
  String _status = "Ready";
  
  // Stored Data
  final List<OneClockCapture> _captures = [];
  final List<int> _recordedBytes = [];
  Int16List? _referencePcmInt16;
  
  // State for playback/vis
  String? _recordedFilePath;
  final AudioPlayer _player = AudioPlayer();
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
      // IMPORTANT: rootBundle can return a view into a larger buffer.
      // We must slice it correctly.
      final data = bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
      
      // Parse Header to get Sample Rate
      final sr = _parseSampleRate(data);
      print("Reference SR: $sr");

      // Extract PCM
      Int16List pcm16 = _extractPcm(data);
      
      // Resample if needed (Target 48000)
      if (sr != 48000) {
        print("Resampling reference from $sr to 48000");
        pcm16 = _resampleLinear(pcm16, sr, 48000);
      }
      
      _referencePcmInt16 = pcm16;

      // Convert to float for visualization
      final floats = Float32List(pcm16.length);
      for (int i = 0; i < pcm16.length; i++) {
        floats[i] = pcm16[i] / 32768.0;
      }
      setState(() {
        _referenceSamples = floats;
      });
    } catch (e) {
      print("Error loading reference: $e");
    }
  }

  int _parseSampleRate(Uint8List data) {
    if (data.length < 44) return 44100; // Fallback
    final view = ByteData.sublistView(data);
    return view.getInt32(24, Endian.little);
  }
  
  Int16List _extractPcm(Uint8List data) {
      // Assume 44 byte header for simple WAVs
      return data.buffer.asInt16List(data.offsetInBytes + 44, (data.length - 44) ~/ 2);
  }

  Int16List _resampleLinear(Int16List input, int srcRate, int dstRate) {
    if (srcRate == dstRate) return input;
    
    final ratio = srcRate / dstRate;
    final outputLength = (input.length / ratio).ceil();
    final output = Int16List(outputLength);
    
    for (int i = 0; i < outputLength; i++) {
      final inputIdx = i * ratio;
      final idx0 = inputIdx.floor();
      final idx1 = idx0 + 1;
      final frac = inputIdx - idx0;
      
      if (idx0 >= input.length) break;
      final val0 = input[idx0];
      final val1 = (idx1 < input.length) ? input[idx1] : val0;
      
      final sample = (val0 + (val1 - val0) * frac).round();
      output[i] = sample;
    }
    return output;
  }

  // ... dispose ...

  Future<void> _start() async {
    if (_running) return;
    try {
      setState(() {
        _status = "Starting...";
        _eventCount = 0;
        _captures.clear();
        _captureVisPoints.clear();
        _recordedFilePath = null;
      });
      
      // ... permission ...

      _sub = OneClockAudio.captureStream.listen((event) {
        if (!mounted) return;
        _captures.add(event); // Store full event for timing
        _recordedBytes.addAll(event.pcm16);

        // Vis logic (downsample)
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
             await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        }
        playbackPath = file.path;
      }
      
      // ... start ...
      // Start engine
      final success = await OneClockAudio.start(OneClockStartConfig(
        playbackWavAssetOrPath: playbackPath,
        sampleRate: 48000,
        channels: 1,
      ));

      if (!success) {
        setState(() => _status = "Error: Engine start failed (check logs)");
      } else {
        setState(() => _running = true);
      }
    } catch (e) {
      // ... error ...
    }
  }

  Future<void> _stop() async {
    if (!_running) return;
    await OneClockAudio.stop();
    _sub?.cancel();
    _sub = null;

    setState(() => _status = "Mixing (Debug Mode)...");

    // Run Debug Mix
    final paths = await _debugMix();
    
    // Play the "Good" mix by default
    final goodPath = paths['good'];

    if (mounted) {
      setState(() {
        _running = false;
        _status = "Stopped. Debug Mix Complete.";
        _recordedFilePath = goodPath;
      });
      print("DEBUG: Recorded path set to: $goodPath");
    }
  }

  // --- DEBUG INSTRUMENTATION ---

  Future<Map<String, String>> _debugMix() async {
    print("\n=== START DEBUG MIX (WavUtil) ===");
    final dir = await getTemporaryDirectory();
    final recPath = '${dir.path}/rec_temp.wav';
    final refPath = '${dir.path}/ref_temp.wav'; // We need ref as file
    final mixPath = '${dir.path}/MIX_GOOD.wav';

    // 1. Save Recording (Flatten captures)
    final rawRecBytes = <int>[];
    for (var c in _captures) rawRecBytes.addAll(c.pcm16);
    final recInt16 = Uint8List.fromList(rawRecBytes).buffer.asInt16List();
    
    // APPLY GAIN BOOST (8.0x) manually before save/mix
    // This addresses "make recorded audio gain louder on wav encoding"
    const double preGain = 8.0;
    print("Applying Pre-Gain: ${preGain}x");
    
    int maxBefore = 0;
    int maxAfter = 0;
    
    for (int i = 0; i < recInt16.length; i++) {
        final original = recInt16[i];
        if (original.abs() > maxBefore) maxBefore = original.abs();
        
        int val = (original * preGain).round();
        if (val > 32767) val = 32767;
        if (val < -32768) val = -32768;
        
        recInt16[i] = val;
        if (val.abs() > maxAfter) maxAfter = val.abs();
    }
    print("GAIN STATS: Max Amp Before=$maxBefore, Max Amp After=$maxAfter");
    
    await WavUtil.writePcm16MonoWav(recPath, recInt16, 48000); // 48k captured

    // 2. Save Reference (Ensure it's a file for WavUtil)
    // We loaded it as bytes, let's write it to temp to be safe/uniform
    if (_referencePcmInt16 != null) {
       await WavUtil.writePcm16MonoWav(refPath, _referencePcmInt16!, 48000);
    }

    // 3. Compute Offset
    int offsetFrames = 0;
    if (_captures.isNotEmpty) {
      offsetFrames = _captures.first.outputFramePos;
    }
    
    // 4. Mix
    print("Mixing with Offset: $offsetFrames frames");
    await WavUtil.mixMonoWithOffsetToWav(
        referencePath: refPath, 
        vocalPath: recPath, 
        offsetFrames: offsetFrames, 
        outputPath: mixPath,
        vocalGain: 1.0, // Pre-gain already applied
    );

    // 5. Debug Prints
    await WavUtil.debugPrintWav(refPath);
    await WavUtil.debugPrintWav(recPath);
    await WavUtil.debugPrintWav(mixPath);

    print("=== END DEBUG MIX ===\n");
    return {'good': mixPath, 'bad': mixPath};
  }

  Uint8List _safeMixMonoPcm16(Int16List ref, List<OneClockCapture> captures, int globalOffsetFrames) {
      // Create output buffer large enough for both
      // 1. Calculate max length
      int refLen = ref.length;
      int recMaxLen = 0;
      for(var c in captures) {
          int end = c.outputFramePos + c.numFrames;
          if (end > recMaxLen) recMaxLen = end;
      }
      int totalLen = (refLen > recMaxLen) ? refLen : recMaxLen;
      // Handle negative offset shift if needed? 
      // For simplicity, we assume outputFramePos >= 0 or we clamp to 0.
      
      final mixBuffer = Int32List(totalLen);
      
      // Accumulate Reference (Headroom 0.5)
      for (int i = 0; i < refLen; i++) {
          mixBuffer[i] += (ref[i] * 0.5).round();
      }
      
      // Accumulate Captures (Headroom 0.5)
      // Captures are disjoint chunks.
      for (var c in captures) {
          final pcm = c.pcm16.buffer.asInt16List();
          int chunkOffset = c.outputFramePos;
          
          for (int i = 0; i < pcm.length; i++) {
              int pos = chunkOffset + i;
              if (pos >= 0 && pos < totalLen) {
                  mixBuffer[pos] += (pcm[i] * 0.5).round();
              }
          }
      }
      
      // Conversion to Int16
      final outBytes = ByteData(totalLen * 2);
      for (int i = 0; i < totalLen; i++) {
          int s = mixBuffer[i];
          // Clamp
          if (s > 32767) s = 32767;
          if (s < -32768) s = -32768;
          outBytes.setInt16(i * 2, s, Endian.little);
      }
      return outBytes.buffer.asUint8List();
  }

  Future<void> _playRecording() async {
    if (_recordedFilePath == null) return;
    // Just play recording
    await _player.play(DeviceFileSource(_recordedFilePath!));
  }

  void _assertOffsetAlignment(int offsetFrames, int channels) {
      int bytesPerFrame = channels * 2;
      int offsetBytes = offsetFrames * bytesPerFrame;
      print("Offset Alignment Check: Frames=$offsetFrames, Bytes=$offsetBytes, BPF=$bytesPerFrame");
      if (offsetBytes % bytesPerFrame != 0) {
          print("!!! CRITICAL ALIGNMENT FAILURE !!!");
      } else {
          print("Alignment OK.");
      }
  }

  void _dumpFirstSamples(String label, Int16List data, int channels) {
      int count = 16;
      if (data.length < count) count = data.length;
      final sb = StringBuffer("$label First $count: ");
      for (int i = 0; i < count; i++) {
          sb.write("${data[i]}, ");
      }
      print(sb.toString());
  }

  void _printWavInfo(String path, Uint8List wavBytes) { // Actually passing raw bytes here for header check
      // Minimal header parse
      if (wavBytes.length < 44) {
          print("WAV Info ($path): Too short!");
          return;
      }
      final view = ByteData.sublistView(wavBytes);
      int riff = view.getUint32(0, Endian.big);
      int wave = view.getUint32(8, Endian.big);
      int sr = view.getUint32(24, Endian.little);
      int channels = view.getUint16(22, Endian.little);
      
      print("WAV Info ($path): RIFF=${riff.toRadixString(16)} WAVE=${wave.toRadixString(16)} SR=$sr Ch=$channels Len=${wavBytes.length}");
  }

  Future<String> _saveWavFile(List<int> pcmData, String filename) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    
    final int sampleRate = 48000;
    final int channels = 1;
    final int byteRate = sampleRate * channels * 2;
    final int dataSize = pcmData.length;
    final int totalSize = 36 + dataSize;
    
    final header = BytesBuilder();
    header.add([0x52, 0x49, 0x46, 0x46]); // RIFF 
    header.add(_int32(totalSize));
    header.add([0x57, 0x41, 0x56, 0x45]); // WAVE
    header.add([0x66, 0x6d, 0x74, 0x20]); // fmt 
    header.add(_int32(16)); 
    header.add(_int16(1)); 
    header.add(_int16(channels));
    header.add(_int32(sampleRate));
    header.add(_int32(byteRate));
    header.add(_int16(channels * 2)); 
    header.add(_int16(16)); 
    header.add([0x64, 0x61, 0x74, 0x61]); // data
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
                        child: const Text("Play mixed recording and reference", textAlign: TextAlign.center),
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
