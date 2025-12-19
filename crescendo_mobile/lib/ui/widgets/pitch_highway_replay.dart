import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/replay_models.dart';

class PitchHighwayReplay extends StatefulWidget {
  final List<TargetNote> targetNotes;
  final List<PitchSample> recordedSamples;
  final int takeDurationMs;
  final double height;
  final bool showControls;

  const PitchHighwayReplay({
    super.key,
    required this.targetNotes,
    required this.recordedSamples,
    required this.takeDurationMs,
    this.height = 380,
    this.showControls = true,
  });

  @override
  State<PitchHighwayReplay> createState() => PitchHighwayReplayState();
}

class PitchHighwayReplayState extends State<PitchHighwayReplay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _playheadMs = 0;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_playing) return;
    setState(() {
      _playheadMs = math.min(
        widget.takeDurationMs,
        _playheadMs + elapsed.inMilliseconds,
      );
      if (_playheadMs >= widget.takeDurationMs) {
        _playing = false;
        _ticker.stop();
      }
    });
  }

  void _togglePlay() {
    setState(() {
      _playing = !_playing;
      if (_playing) {
        _ticker.start();
      } else {
        _ticker.stop();
      }
    });
  }

  void _replay() {
    setState(() {
      _playheadMs = 0;
      _playing = true;
      _ticker.start();
    });
  }

  void replay() => _replay();

  @override
  Widget build(BuildContext context) {
    final durationMs = widget.takeDurationMs > 0 ? widget.takeDurationMs : 6000;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              const topPad = 12.0;
              const bottomPad = 12.0;
              final viewport = _computeViewport(widget.targetNotes, widget.recordedSamples);
              final targetLayer = _NotesPainter(
                notes: widget.targetNotes,
                durationMs: durationMs,
                minMidi: viewport.$1,
                maxMidi: viewport.$2,
                topPad: topPad,
                bottomPad: bottomPad,
              );
              final contourLayer = _ContourPainter(
                samples: widget.recordedSamples,
                durationMs: durationMs,
                minMidi: viewport.$1,
                maxMidi: viewport.$2,
                topPad: topPad,
                bottomPad: bottomPad,
              );
              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _GridPainter(
                        minMidi: viewport.$1,
                        maxMidi: viewport.$2,
                        topPad: topPad,
                        bottomPad: bottomPad,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: targetLayer,
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: contourLayer,
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _PlayheadPainter(
                        x: _timeToX(_playheadMs, durationMs, width),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        if (widget.showControls)
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _togglePlay,
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                label: Text(_playing ? 'Pause' : 'Play'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _replay,
                icon: const Icon(Icons.replay),
                label: const Text('Replay'),
              ),
            ],
          ),
      ],
    );
  }

  (double, double) _computeViewport(
    List<TargetNote> notes,
    List<PitchSample> samples,
  ) {
    final noteMidis = notes.map((n) => n.midi).toList();
    final sampleMidis = samples
        .map((s) => s.midi ?? _hzToMidi(s.freqHz))
        .whereType<double>()
        .toList();
    final source = noteMidis.isNotEmpty ? noteMidis : sampleMidis;
    if (source.isEmpty) return (48, 72);
    final min = source.reduce(math.min) - 3;
    final max = source.reduce(math.max) + 3;
    return (min, max);
  }

  double _hzToMidi(double? hz) {
    if (hz == null || hz <= 0 || hz.isNaN || hz.isInfinite) return double.nan;
    return 69 + 12 * (math.log(hz / 440.0) / math.ln2);
  }
}

double _midiToY(
  double midi,
  double minMidi,
  double maxMidi,
  double height,
  double topPad,
  double bottomPad,
) {
  final clamped = midi.clamp(minMidi, maxMidi);
  final usableHeight = (height - topPad - bottomPad).clamp(1.0, height);
  final ratio = (clamped - minMidi) / (maxMidi - minMidi);
  return (height - bottomPad) - ratio * usableHeight;
}

double _timeToX(int timeMs, int durationMs, double width) {
  if (durationMs <= 0) return 0;
  final clamped = timeMs.clamp(0, durationMs).toDouble();
  return (clamped / durationMs) * width;
}

class _NotesPainter extends CustomPainter {
  final List<TargetNote> notes;
  final int durationMs;
  final double minMidi;
  final double maxMidi;
  final double topPad;
  final double bottomPad;

  _NotesPainter({
    required this.notes,
    required this.durationMs,
    required this.minMidi,
    required this.maxMidi,
    required this.topPad,
    required this.bottomPad,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFFFC978);
    const barHeight = 18.0;
    final radius = Radius.circular(barHeight / 2);

    for (final n in notes) {
      final left = _timeToX(n.startMs, durationMs, size.width);
      final right = _timeToX(n.endMs, durationMs, size.width);
      final y = _midiToY(n.midi, minMidi, maxMidi, size.height, topPad, bottomPad);
      final rect = RRect.fromLTRBR(
        left,
        y - barHeight / 2,
        right,
        y + barHeight / 2,
        radius,
      );
      canvas.drawRRect(rect, paint);
      if (n.label != null && n.label!.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: n.label,
            style: const TextStyle(color: Colors.black87, fontSize: 12),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: math.max(0, right - left - 6));
        tp.paint(canvas, Offset(left + 4, y - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NotesPainter oldDelegate) {
    return oldDelegate.notes != notes ||
        oldDelegate.durationMs != durationMs ||
        oldDelegate.minMidi != minMidi ||
        oldDelegate.maxMidi != maxMidi;
  }
}

class _ContourPainter extends CustomPainter {
  final List<PitchSample> samples;
  final int durationMs;
  final double minMidi;
  final double maxMidi;
  final double topPad;
  final double bottomPad;

  _ContourPainter({
    required this.samples,
    required this.durationMs,
    required this.minMidi,
    required this.maxMidi,
    required this.topPad,
    required this.bottomPad,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final filtered = _smoothSamples(_validSamples(samples));
    if (filtered.isEmpty) return;
    final path = Path();
    bool started = false;
    for (final s in filtered) {
      if (s.timeMs < 0 || s.timeMs > durationMs) continue;
      final x = _timeToX(s.timeMs, durationMs, size.width);
      final y = _midiToY(s.midi!, minMidi, maxMidi, size.height, topPad, bottomPad);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFFFB347);
    canvas.drawPath(path, paint);
  }

  List<PitchSample> _validSamples(List<PitchSample> samples) {
    return samples.where((s) {
      final midi = s.midi ?? _hzToMidi(s.freqHz);
      return midi != null && midi.isFinite;
    }).map((s) {
      final midi = s.midi ?? _hzToMidi(s.freqHz);
      return PitchSample(timeMs: s.timeMs, midi: midi);
    }).toList();
  }

  List<PitchSample> _smoothSamples(List<PitchSample> samples) {
    if (samples.length < 3) return samples;
    final smoothed = <PitchSample>[];
    for (var i = 0; i < samples.length; i++) {
      final start = math.max(0, i - 2);
      final end = math.min(samples.length - 1, i + 2);
      var sum = 0.0;
      var count = 0;
      for (var j = start; j <= end; j++) {
        sum += samples[j].midi ?? 0;
        count++;
      }
      smoothed.add(PitchSample(
        timeMs: samples[i].timeMs,
        midi: sum / count,
      ));
    }
    return smoothed;
  }

  double? _hzToMidi(double? hz) {
    if (hz == null || hz <= 0 || hz.isNaN || hz.isInfinite) return null;
    return 69 + 12 * (math.log(hz / 440.0) / math.ln2);
  }

  @override
  bool shouldRepaint(covariant _ContourPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.durationMs != durationMs ||
        oldDelegate.minMidi != minMidi ||
        oldDelegate.maxMidi != maxMidi;
  }
}

class _GridPainter extends CustomPainter {
  final double minMidi;
  final double maxMidi;
  final double topPad;
  final double bottomPad;

  _GridPainter({
    required this.minMidi,
    required this.maxMidi,
    required this.topPad,
    required this.bottomPad,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE6EEF3)
      ..strokeWidth = 1;
    final steps = 5;
    for (var i = 0; i <= steps; i++) {
      final midi = minMidi + (maxMidi - minMidi) * (i / steps);
      final y = _midiToY(midi, minMidi, maxMidi, size.height, topPad, bottomPad);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.minMidi != minMidi || oldDelegate.maxMidi != maxMidi;
  }
}

class _PlayheadPainter extends CustomPainter {
  final double x;

  _PlayheadPainter({required this.x});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blueGrey.withOpacity(0.7)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _PlayheadPainter oldDelegate) {
    return oldDelegate.x != x;
  }
}
