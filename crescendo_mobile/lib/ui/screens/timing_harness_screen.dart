import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/reference_note.dart';
import '../../services/audio_synth_service.dart';
import '../../utils/performance_clock.dart';
import '../theme/app_theme.dart';
import '../widgets/debug_overlay.dart';

/// Timing harness:
/// - Expect audioPositionMs vs visualTimeMs delta within +/-20ms (ideal),
///   and within +/-40ms acceptable after offset tuning.
class TimingHarnessScreen extends StatefulWidget {
  const TimingHarnessScreen({super.key});

  @override
  State<TimingHarnessScreen> createState() => _TimingHarnessScreenState();
}

class _TimingHarnessScreenState extends State<TimingHarnessScreen>
    with SingleTickerProviderStateMixin {
  final pixelsPerSecond = 220.0;
  final playheadFraction = 0.5;
  final PerformanceClock _clock = PerformanceClock();
  final _timeNotifier = ValueNotifier<double>(0);

  late final Ticker _ticker;
  late final AudioSynthService _synth;
  late final double _audioLatencyMs;
  StreamSubscription<Duration>? _audioPosSub;
  double? _audioPositionSec;
  bool _audioStarted = false;

  final List<double> _beatTimes = [];
  List<ReferenceNote> _clickNotes = [];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _synth = AudioSynthService();
    _audioLatencyMs = kIsWeb ? 0 : (Platform.isIOS ? 150.0 : 200.0);
    _clock.setAudioPositionProvider(() => _audioPositionSec);
    _clock.setLatencyCompensationMs(_audioLatencyMs);
    _buildClicks(bpm: 120, beats: 16);
    _start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _audioPosSub?.cancel();
    _synth.stop();
    _timeNotifier.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final now = _clock.nowSeconds();
    _timeNotifier.value = now;
  }

  void _buildClicks({required double bpm, required int beats}) {
    _beatTimes.clear();
    _clickNotes = [];
    final beatSec = 60.0 / bpm;
    for (var i = 0; i < beats; i++) {
      final start = i * beatSec;
      _beatTimes.add(start);
      _clickNotes.add(ReferenceNote(
        startSec: start,
        endSec: start + 0.04,
        midi: 84,
        lyric: null,
      ));
    }
  }

  Future<void> _start() async {
    _audioPositionSec = null;
    _audioStarted = false;
    _clock.start(freezeUntilAudio: true);
    _ticker.start();
    final path = await _synth.renderReferenceNotes(_clickNotes);
    await _synth.stop();
    await _synth.playFile(path);
    await _audioPosSub?.cancel();
    _audioPosSub = _synth.onPositionChanged.listen((pos) {
      if (!_audioStarted && pos > Duration.zero) {
        _audioStarted = true;
      }
      if (_audioStarted) {
        _audioPositionSec = pos.inMilliseconds / 1000.0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Timing Harness')),
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _TimingHarnessPainter(
                time: _timeNotifier,
                beatTimes: _beatTimes,
                pixelsPerSecond: pixelsPerSecond,
                playheadFraction: playheadFraction,
                colors: colors,
              ),
            ),
          ),
          DebugOverlay(
            audioPositionMs: _audioPositionSec == null ? null : _audioPositionSec! * 1000.0,
            visualTimeMs: _timeNotifier.value * 1000.0,
            pitchLagMs: null,
            offsetMs: 0,
            onOffsetChange: (_) {},
            label: 'Timing Harness',
          ),
        ],
      ),
    );
  }
}

class _TimingHarnessPainter extends CustomPainter {
  final ValueListenable<double> time;
  final List<double> beatTimes;
  final double pixelsPerSecond;
  final double playheadFraction;
  final AppThemeColors colors;

  _TimingHarnessPainter({
    required this.time,
    required this.beatTimes,
    required this.pixelsPerSecond,
    required this.playheadFraction,
    required this.colors,
  }) : super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) {
    final currentTime = time.value;
    final playheadX = size.width * playheadFraction;
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          colors.bgTop,
          colors.bgBottom,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    final markerPaint = Paint()
      ..color = colors.textPrimary.withOpacity(0.6)
      ..strokeWidth = 2.0;
    for (final beat in beatTimes) {
      final x = playheadX + (beat - currentTime) * pixelsPerSecond;
      if (x < -40 || x > size.width + 40) continue;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), markerPaint);
    }

    final playheadPaint = Paint()
      ..color = colors.blueAccent.withOpacity(0.8)
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(playheadX, 0), Offset(playheadX, size.height), playheadPaint);
  }

  @override
  bool shouldRepaint(covariant _TimingHarnessPainter oldDelegate) {
    return oldDelegate.beatTimes != beatTimes ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.playheadFraction != playheadFraction ||
        oldDelegate.colors != colors;
  }
}
