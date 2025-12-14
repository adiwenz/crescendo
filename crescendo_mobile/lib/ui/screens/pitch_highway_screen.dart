import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/pitch_frame.dart';
import '../../models/reference_note.dart';
import '../../services/pitch_detection_service.dart';
import '../widgets/pitch_highway_painter.dart';

class PitchHighwayScreen extends StatefulWidget {
  const PitchHighwayScreen({super.key});

  @override
  State<PitchHighwayScreen> createState() => _PitchHighwayScreenState();
}

class _PitchHighwayScreenState extends State<PitchHighwayScreen> with SingleTickerProviderStateMixin {
  final pixelsPerSecond = 160.0;
  final playheadFraction = 0.45;
  final tailWindowSec = 4.0;
  final midiRange = const (min: 48, max: 72);

  final _timeNotifier = ValueNotifier<double>(0);
  final _pitchTail = <PitchFrame>[];

  late final Ticker _ticker;
  Duration? _lastTick;
  bool _playing = false;

  late final PitchDetectionService _pitchService;
  StreamSubscription<PitchFrame>? _pitchSub;

  List<ReferenceNote> get _stubNotes => const [
        ReferenceNote(startSec: 0, endSec: 1.2, midi: 60, lyric: 'A'),
        ReferenceNote(startSec: 1.35, endSec: 2.4, midi: 62, lyric: 'new'),
        ReferenceNote(startSec: 2.5, endSec: 3.4, midi: 64, lyric: 'fan-'),
        ReferenceNote(startSec: 3.45, endSec: 4.4, midi: 65, lyric: 'tas-'),
        ReferenceNote(startSec: 4.6, endSec: 5.3, midi: 64, lyric: 'tic'),
        ReferenceNote(startSec: 5.5, endSec: 6.4, midi: 62, lyric: 'point'),
        ReferenceNote(startSec: 6.6, endSec: 7.2, midi: 60, lyric: 'of'),
        ReferenceNote(startSec: 7.35, endSec: 8.4, midi: 59, lyric: 'view'),
        ReferenceNote(startSec: 8.6, endSec: 9.6, midi: 60, lyric: 'yeah'),
      ];

  double get _totalDuration => _stubNotes.map((n) => n.endSec).fold(0.0, math.max) + 1.0;

  @override
  void initState() {
    super.initState();
    _pitchService = PitchDetectionService();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pitchSub?.cancel();
    _pitchService.stopStream();
    _timeNotifier.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_playing) return;
    final dt = elapsed - (_lastTick ?? elapsed);
    _lastTick = elapsed;
    _advance(dt.inMicroseconds / 1e6);
  }

  void _advance(double deltaSeconds) {
    final next = _timeNotifier.value + deltaSeconds;
    _timeNotifier.value = next;
    _trimTail();
    if (next > _totalDuration) {
      unawaited(_togglePlayback(force: false));
    }
  }

  Future<void> _togglePlayback({bool? force}) async {
    final target = force ?? !_playing;
    if (target == _playing) return;
    if (target) {
      _playing = true;
      _lastTick = null;
      _ticker.start();
      await _startPitchStream();
    } else {
      _playing = false;
      _ticker.stop();
      _lastTick = null;
      await _pitchService.stopStream();
      await _pitchSub?.cancel();
      _pitchSub = null;
    }
    setState(() {});
  }

  Future<void> _startPitchStream() async {
    await _pitchSub?.cancel();
    final stream = await _pitchService.startStream();
    _pitchSub = stream.listen((frame) {
      final midi = frame.midi ?? (frame.hz != null ? _hzToMidi(frame.hz!) : null);
      if (midi == null) return;
      _pitchTail.add(PitchFrame(time: _timeNotifier.value, hz: frame.hz, midi: midi));
      _trimTail();
      // Nudge repaint even if time doesn't change.
      _timeNotifier.value = _timeNotifier.value;
    });
  }

  void _trimTail() {
    final cutoff = _timeNotifier.value - tailWindowSec;
    final idx = _pitchTail.indexWhere((f) => f.time >= cutoff);
    if (idx > 0) {
      _pitchTail.removeRange(0, idx);
    } else if (idx == -1 && _pitchTail.isNotEmpty) {
      _pitchTail.clear();
    }
  }

  double _hzToMidi(double hz) => 69 + 12 * math.log(hz / 440) / math.ln2;

  String _formatTime(double t) {
    final totalSeconds = t.clamp(0, 24 * 60 * 60).floor();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bg = const Color(0xFF4020B8);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Pitch Highway'),
        backgroundColor: bg,
        foregroundColor: Colors.white,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('CHORUS 1', style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1.2)),
                Row(
                  children: [
                    Icon(Icons.favorite_border, color: Colors.white70),
                    SizedBox(width: 12),
                    Icon(Icons.mobile_screen_share, color: Colors.white70),
                    SizedBox(width: 12),
                    Icon(Icons.close, color: Colors.white70),
                  ],
                )
              ],
            ),
          ),
          SizedBox(
            height: 260,
            child: CustomPaint(
              painter: PitchHighwayPainter(
                notes: _stubNotes,
                pitchTail: _pitchTail,
                time: _timeNotifier,
                pixelsPerSecond: pixelsPerSecond,
                playheadFraction: playheadFraction,
                tailWindowSec: tailWindowSec,
                midiMin: midiRange.min,
                midiMax: midiRange.max,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: _timeNotifier,
                  builder: (_, v, __) => Text(_formatTime(v), style: const TextStyle(color: Colors.white70)),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white30,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      alignment: Alignment.centerLeft,
                      child: ValueListenableBuilder<double>(
                        valueListenable: _timeNotifier,
                        builder: (_, v, __) {
                          final pct = (v / _totalDuration).clamp(0.0, 1.0);
                          return FractionallySizedBox(
                            widthFactor: pct,
                            child: Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Text(_formatTime(_totalDuration), style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => _togglePlayback(),
                  iconSize: 40,
                  color: Colors.white,
                  icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Pitch offset', style: TextStyle(color: Colors.white70)),
                    Text('+0.0 c', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: const [
                    Text('Accuracy', style: TextStyle(color: Colors.white70)),
                    Text('50%', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
