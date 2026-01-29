import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/replay_models.dart';
import '../../utils/pitch_math.dart';

class OverviewGraph extends StatelessWidget {
  final List<PitchSample> samples;
  final List<dynamic> segments; // dynamic to avoid tight model coupling if needed, but usually ExerciseSegment
  final int durationMs;

  const OverviewGraph({
    super.key,
    required this.samples,
    this.segments = const [],
    required this.durationMs,
  });

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) return const SizedBox.shrink();

    // Compute midis from samples only
    final sampleMidis = samples
        .map((s) =>
            s.midi ?? (s.freqHz != null ? PitchMath.hzToMidi(s.freqHz!) : null))
        .whereType<double>()
        .toList();
    if (sampleMidis.isEmpty) return const SizedBox.shrink();

    final minMidi = sampleMidis.reduce(math.min) - 3;
    final maxMidi = sampleMidis.reduce(math.max) + 3;

    // Smooth samples for readability (keeps original timeMs)
    final smoothed = _smoothSamples(samples);

    // Compute sample-only time domain (this trims left whitespace)
    final domain = _computeSampleDomain(smoothed);
    final domainStartMs = domain.$1;
    final domainDurationMs = domain.$2;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: const Color(0xFFF0F3F6)),
      ),
      child: SizedBox(
        height: 200,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            const topPad = 8.0;
            const bottomPad = 8.0;

            return Stack(
              children: [
                // Grid lines
                CustomPaint(
                  size: Size(width, height),
                  painter: _OverviewGridPainter(
                    minMidi: minMidi,
                    maxMidi: maxMidi,
                    topPad: topPad,
                    bottomPad: bottomPad,
                  ),
                ),

                // Pitch contour line (sample-only domain)
                CustomPaint(
                  size: Size(width, height),
                  painter: _OverviewContourPainter(
                    samples: smoothed,
                    domainStartMs: domainStartMs,
                    domainDurationMs: domainDurationMs,
                    minMidi: minMidi,
                    maxMidi: maxMidi,
                    topPad: topPad,
                    bottomPad: bottomPad,
                  ),
                ),

                // Segment markers (rebased to sample-only domain)
                if (segments.isNotEmpty)
                  ...segments.map((segment) {
                    // Try to access startMs if it exists on the segment object
                    final int startMs = (segment as dynamic).startMs is int ? (segment as dynamic).startMs : 0;
                    final x = _timeToX(
                      startMs,
                      width,
                      domainStartMs,
                      domainDurationMs,
                    );
                    return Positioned(
                      left: x.clamp(0.0, width - 1),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 1,
                        color: Colors.blue.withOpacity(0.15),
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Returns (domainStartMs, domainDurationMs) computed ONLY from samples.
  /// Starts exactly at the first recorded sample -> no left whitespace.
  (int, int) _computeSampleDomain(List<PitchSample> samples) {
    if (samples.isEmpty) return (0, 1);

    var minMs = samples.first.timeMs;
    var maxMs = samples.first.timeMs;
    for (final s in samples) {
      if (s.timeMs < minMs) minMs = s.timeMs;
      if (s.timeMs > maxMs) maxMs = s.timeMs;
    }
    final dur = math.max(1, maxMs - minMs);
    return (minMs, dur);
  }

  double _timeToX(
      int timeMs, double width, int domainStartMs, int domainDurationMs) {
    if (domainDurationMs <= 0) return 0;
    final t = (timeMs - domainStartMs) / domainDurationMs;
    return (t.clamp(0.0, 1.0)) * width;
  }

  List<PitchSample> _smoothSamples(List<PitchSample> samples) {
    if (samples.length < 3) return samples;
    final smoothed = <PitchSample>[];

    for (var i = 0; i < samples.length; i++) {
      final midi = samples[i].midi ??
          (samples[i].freqHz != null
              ? PitchMath.hzToMidi(samples[i].freqHz!)
              : null);
      if (midi == null) continue;

      // Simple moving average with window of 3
      var sum = midi;
      var count = 1;

      if (i > 0) {
        final prevMidi = samples[i - 1].midi ??
            (samples[i - 1].freqHz != null
                ? PitchMath.hzToMidi(samples[i - 1].freqHz!)
                : null);
        if (prevMidi != null) {
          sum += prevMidi;
          count++;
        }
      }

      if (i < samples.length - 1) {
        final nextMidi = samples[i + 1].midi ??
            (samples[i + 1].freqHz != null
                ? PitchMath.hzToMidi(samples[i + 1].freqHz!)
                : null);
        if (nextMidi != null) {
          sum += nextMidi;
          count++;
        }
      }

      smoothed.add(PitchSample(
        timeMs: samples[i].timeMs, // IMPORTANT: keep original timeMs
        midi: sum / count,
        freqHz: samples[i].freqHz,
      ));
    }

    return smoothed;
  }
}

class _OverviewGridPainter extends CustomPainter {
  final double minMidi;
  final double maxMidi;
  final double topPad;
  final double bottomPad;

  _OverviewGridPainter({
    required this.minMidi,
    required this.maxMidi,
    required this.topPad,
    required this.bottomPad,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE6EEF3)
      ..strokeWidth = 1;

    for (var i = 0; i <= 4; i++) {
      final midi = minMidi + (maxMidi - minMidi) * (i / 4);
      final y =
          _midiToY(midi, minMidi, maxMidi, size.height, topPad, bottomPad);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OverviewGridPainter oldDelegate) => false;

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
    final denom =
        (maxMidi - minMidi).abs() < 0.0001 ? 1.0 : (maxMidi - minMidi);
    final ratio = (clamped - minMidi) / denom;
    return (height - bottomPad) - ratio * usableHeight;
  }
}

class _OverviewContourPainter extends CustomPainter {
  final List<PitchSample> samples;

  /// Sample-only x domain:
  /// x = (timeMs - domainStartMs) / domainDurationMs
  final int domainStartMs;
  final int domainDurationMs;

  final double minMidi;
  final double maxMidi;
  final double topPad;
  final double bottomPad;

  _OverviewContourPainter({
    required this.samples,
    required this.domainStartMs,
    required this.domainDurationMs,
    required this.minMidi,
    required this.maxMidi,
    required this.topPad,
    required this.bottomPad,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    bool started = false;

    for (final s in samples) {
      final midi =
          s.midi ?? (s.freqHz != null ? PitchMath.hzToMidi(s.freqHz!) : null);
      if (midi == null || !midi.isFinite) continue;

      final x = _timeToX(s.timeMs, size.width, domainStartMs, domainDurationMs);
      final y =
          _midiToY(midi, minMidi, maxMidi, size.height, topPad, bottomPad);

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    final contourPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFFFB347);

    if (started) {
      canvas.drawPath(path, contourPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OverviewContourPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.domainStartMs != domainStartMs ||
        oldDelegate.domainDurationMs != domainDurationMs ||
        oldDelegate.minMidi != minMidi ||
        oldDelegate.maxMidi != maxMidi;
  }

  double _timeToX(
      int timeMs, double width, int domainStartMs, int domainDurationMs) {
    if (domainDurationMs <= 0) return 0;
    final t = (timeMs - domainStartMs) / domainDurationMs;
    return (t.clamp(0.0, 1.0)) * width;
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
    final denom =
        (maxMidi - minMidi).abs() < 0.0001 ? 1.0 : (maxMidi - minMidi);
    final ratio = (clamped - minMidi) / denom;
    return (height - bottomPad) - ratio * usableHeight;
  }
}
