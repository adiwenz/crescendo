import 'dart:async';
import 'dart:math';
import 'package:crescendo_mobile/services/timestamp_sync_service.dart';
import 'package:flutter/material.dart';


// PUBSPEC INSTRUCTIONS:
// Ensure the following is in your pubspec.yaml under flutter -> assets:
//   - assets/audio/ref.wav

class TimestampSyncTestScreen extends StatefulWidget {
  const TimestampSyncTestScreen({super.key});

  @override
  State<TimestampSyncTestScreen> createState() => _TimestampSyncTestScreenState();
}

class _TimestampSyncTestScreenState extends State<TimestampSyncTestScreen> {
  final TimestampSyncService _service = TimestampSyncService();
  
  // State for UI
  bool _isArmed = false;
  bool _isRunning = false;
  SyncRunResult? _lastResult;


  final String _assetPath = 'assets/audio/reference.wav';
  // NOTE: If you have 'assets/audio/reference.wav' instead, change the above line.

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    try {
      await _service.init();
      _appendLog('Service initialized.');
    } catch (e) {
      _appendLog('Error initializing: $e');
    }
  }

  void _appendLog(String msg) {
    debugPrint('[SyncScreen] $msg');
  }

  // Pitch State
  double? _currentHz;
  String? _currentNote;
  final List<double?> _pitchHistory = [];
  StreamSubscription? _pitchSub;
  bool _livePitchEnabled = true;
  
  // Mute State
  bool _isReferenceMuted = false;
  bool _isRecordingMuted = false;

  @override
  void dispose() {
    _pitchSub?.cancel();
    _service.dispose();
    super.dispose();
  }

  Future<void> _onArm() async {
    try {
      await _service.arm(refAssetPath: _assetPath);
      setState(() {
        _isArmed = true;
        _lastResult = null;
        _pitchHistory.clear();
        _currentHz = null;
        _currentNote = null;
      });
      _appendLog('Armed.');
    } catch (e) {
      _appendLog('Arm failed: $e');
    }
  }

  Future<void> _onStartRun() async {
    if (!_isArmed) return;
    setState(() {
      _isRunning = true;
      _pitchHistory.clear();
    });
    
    // Subscribe to pitch if enabled
    if (_livePitchEnabled) {
      _pitchSub?.cancel();
      _pitchSub = _service.pitchStream.listen((hz) {
        if (!mounted) return;
        setState(() {
          _currentHz = hz;
          if (hz != null && hz > 0) {
            _currentNote = _hzToNote(hz);
          } else {
             _currentNote = null;
          }
          
          _pitchHistory.add(hz);
          if (_pitchHistory.length > 100) {
            _pitchHistory.removeAt(0);
          }
        });
      });
    }
    
    try {
      final result = await _service.startRun(refAssetPath: _assetPath);
      setState(() {
        _appendLog('Run started. RecStart: ${result.recStartNs}');
      });
    } catch (e) {
      _appendLog('Start run failed: $e');
      setState(() {
        _isRunning = false;
      });
      _pitchSub?.cancel();
    }
  }

  Future<void> _onStopAndAlign() async {
    if (!_isRunning) return;
    _pitchSub?.cancel();
    
    try {
      final result = await _service.stopRunAndAlign();
      setState(() {
        _lastResult = result;
        _isRunning = false;
        _isArmed = false; 
      });
      _appendLog('Stopped. Pitch frames: ${_pitchHistory.length}');
      
    } catch (e) {
      _appendLog('Stop failed: $e');
      setState(() {
        _isRunning = false;
      });
    }
  }

  Future<void> _onPlayAligned() async {
    if (_lastResult == null) return;
    try {
      _appendLog('Playing aligned...');
      await _service.playAligned();
    } catch (e) {
      _appendLog('Play failed: $e');
    }
  }
  
  void _toggleReferenceMute() {
    setState(() {
      _isReferenceMuted = !_isReferenceMuted;
    });
    _service.setMuteRef(_isReferenceMuted);
    _appendLog('Reference ${_isReferenceMuted ? "muted" : "unmuted"}');
  }
  
  void _toggleRecordingMute() {
    setState(() {
      _isRecordingMuted = !_isRecordingMuted;
    });
    _service.setMuteRec(_isRecordingMuted);
    _appendLog('Recording ${_isRecordingMuted ? "muted" : "unmuted"}');
  }
  
  String _hzToNote(double hz) {
    // Simple Hz to Note
    // A4 = 440
    // n = 12 * log2(hz/440) + 69  (MIDI)
    // MIDI 69 = A4
    if (hz <= 0) return '';
    final midi = 69 + 12 * (log(hz / 440.0) / ln2);
    final noteIndex = midi.round() % 12;
    final octave = (midi.round() / 12).floor() - 1;
    const notes = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final noteName = notes[noteIndex];
    
    // Cents
    final cents = (midi - midi.round()) * 100;
    final centsStr = cents >= 0 ? '+${cents.toStringAsFixed(0)}' : cents.toStringAsFixed(0);
    
    return '$noteName$octave ($centsStr)';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Timestamp Sync Test')),
      body: Column(
        children: [
          // Controls
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Row(
                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                   children: [
                     const Text('Live Pitch Tracking'),
                     Switch(value: _livePitchEnabled, onChanged: (v) => setState(() => _livePitchEnabled = v)),
                   ],
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton(
                      onPressed: _isRunning ? null : _onArm,
                      child: const Text('1. Arm'),
                    ),
                    ElevatedButton(
                      onPressed: (_isArmed && !_isRunning) ? _onStartRun : null,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade100),
                      child: const Text('2. Start Run'),
                    ),
                    ElevatedButton(
                      onPressed: _isRunning ? _onStopAndAlign : null,
                       style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade100),
                      child: const Text('3. Stop & Align'),
                    ),
                    ElevatedButton(
                      onPressed: (!_isRunning && _lastResult != null) ? _onPlayAligned : null,
                      child: const Text('4. Play Aligned'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Column(
                      children: [
                        IconButton(
                          icon: Icon(
                            _isReferenceMuted ? Icons.volume_off : Icons.volume_up,
                            color: _isReferenceMuted ? Colors.red : Colors.blue,
                          ),
                          onPressed: _toggleReferenceMute,
                          tooltip: _isReferenceMuted ? 'Unmute Reference' : 'Mute Reference',
                        ),
                        const Text('Reference', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    const SizedBox(width: 40),
                    Column(
                      children: [
                        IconButton(
                          icon: Icon(
                            _isRecordingMuted ? Icons.volume_off : Icons.volume_up,
                            color: _isRecordingMuted ? Colors.red : Colors.green,
                          ),
                          onPressed: _toggleRecordingMute,
                          tooltip: _isRecordingMuted ? 'Unmute Recording' : 'Mute Recording',
                        ),
                        const Text('Recording', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Live Pitch UI
          if (_isRunning)
          Container(
            height: 120,
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(border: Border.all(color: Colors.blueAccent), borderRadius: BorderRadius.circular(8)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _currentHz != null ? '${_currentHz!.toStringAsFixed(1)} Hz' : '—', 
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                Text(
                  _currentNote ?? '', 
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 30,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: PitchHistoryPainter(_pitchHistory),
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(),
          
          // Results Area
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              color: Colors.grey.shade100,
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                child: _lastResult == null 
                  ? const Text('No result yet.') 
                  : SelectableText(
                      'RESULTS:\n'
                      '-----------------\n'
                      '${_lastResult.toString()}\n\n'
                      'PATHS:\n'
                      'Raw: ${_lastResult!.rawRecordingPath}\n'
                      'Aligned: ${_lastResult!.alignedRecordingPath}\n'
                    ),
              ),
            ),
          ),
          
        ],
      ),
    );
  }
}

class PitchHistoryPainter extends CustomPainter {
  final List<double?> history;
  PitchHistoryPainter(this.history);
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.blue..strokeWidth = 2;
    final w = size.width / 100; // fit 100 samples
    
    // Scale usually 0 to 1000hz?
    // Let's dynamic scale
    // Or just visible presence
    
    for (int i = 0; i < history.length; i++) {
        final hz = history[i];
        if (hz != null && hz > 0) {
            // Log scale for pitch usually better but linear 0-1000 is fine for debug
            final h = (hz / 1000.0).clamp(0.0, 1.0) * size.height;
            canvas.drawLine(
               Offset(i * w, size.height), 
               Offset(i * w, size.height - h), 
               paint
            );
        }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
