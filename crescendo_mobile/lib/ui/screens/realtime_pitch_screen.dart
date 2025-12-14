import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/pitch_frame.dart';
import '../../services/pitch_history_buffer.dart';
import '../../services/recording_service.dart';
import '../widgets/realtime_pitch_painter.dart';

class RealtimePitchScreen extends StatefulWidget {
  const RealtimePitchScreen({super.key});

  @override
  State<RealtimePitchScreen> createState() => _RealtimePitchScreenState();
}

class _RealtimePitchScreenState extends State<RealtimePitchScreen> {
  final history = PitchHistoryBuffer(capacity: 200);
  final RecordingService _recording = RecordingService();
  StreamSubscription<PitchFrame>? _liveSub;
  bool _listening = false;
  String _status = 'Idle';

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _status = 'Starting...');
    try {
      history.clear();
      await _recording.start();
      _liveSub = _recording.liveStream.listen((pf) {
        if (pf.hz != null ||
            (history.frames.isNotEmpty && history.frames.last.hz != null)) {
          history.add(PitchFrame(
              time: pf.time, hz: pf.hz, midi: pf.midi, centsError: pf.centsError));
        }
        setState(() {});
      }, onError: (e) {
        setState(() => _status = 'Audio error: $e');
      });

      setState(() {
        _listening = true;
        _status = 'Listening...';
      });
    } catch (e) {
      setState(() {
        _listening = false;
        _status = 'Start failed: $e';
      });
    }
  }

  Future<void> _stop() async {
    await _liveSub?.cancel();
    await _recording.stop();
    setState(() {
      _listening = false;
      _status = 'Stopped';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Realtime Pitch')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _listening ? null : _start,
                  child: const Text('Start'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _listening ? _stop : null,
                  child: const Text('Stop'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white,
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 6)
                  ],
                ),
                child: CustomPaint(
                  painter: PitchTailPainter(
                      frames: history.frames, minMidi: 48, maxMidi: 84),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
