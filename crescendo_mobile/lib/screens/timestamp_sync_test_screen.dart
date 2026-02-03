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
  final List<String> _logs = [];

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
    if (!mounted) return;
    setState(() {
      _logs.add(msg);
    });
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _onArm() async {
    try {
      await _service.arm(refAssetPath: _assetPath);
      setState(() {
        _isArmed = true;
        _lastResult = null;
        _logs.clear(); // Clear previous run logs from UI
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
    });
    
    try {
      final result = await _service.startRun(refAssetPath: _assetPath);
      // Intermediate update (timestamps captured)
      setState(() {
        // We can show partial results here if we want, but startRun returns
        // roughly when recording starts.
        _appendLog('Run started. RecStart: ${result.recStartNs}');
      });
    } catch (e) {
      _appendLog('Start run failed: $e');
      setState(() {
        _isRunning = false;
      });
    }
  }

  Future<void> _onStopAndAlign() async {
    if (!_isRunning) return;
    
    try {
      final result = await _service.stopRunAndAlign();
      setState(() {
        _lastResult = result;
        _isRunning = false;
        _isArmed = false; // Need to re-arm for next time usually
      });
      
      // Pull logs from service to show full detail
      setState(() {
        _logs.addAll(result.logs.where((l) => !_logs.contains(l)));
      });
      
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Timestamp Sync Test')),
      body: Column(
        children: [
          // Controls
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Wrap(
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
          
          const Divider(height: 1),
          const Text('LOGS', style: TextStyle(fontWeight: FontWeight.bold)),
          
          // Logs Area
          Expanded(
            flex: 3,
            child: ListView.builder(
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Text(
                    _logs[index], 
                    style: const TextStyle(fontFamily: 'Courier', fontSize: 12),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
