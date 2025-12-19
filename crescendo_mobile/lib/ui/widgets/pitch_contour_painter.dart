import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/pitch_frame.dart';
import '../../utils/pitch_math.dart';

class PitchContourPainter extends CustomPainter {
  final List<PitchFrame> frames;
  final ValueListenable<double> time;
  final double pixelsPerSecond;
  final double playheadFraction;
  final int midiMin;
  final int midiMax;
  final double confidenceThreshold;
  final double rmsThreshold;
  final double maxGapSec;
  final Color glowColor;
  final Color coreColor;
  final bool debugLogMapping;

  static final Set<int> _loggedContourPainters = <int>{};

  PitchContourPainter({
    required this.frames,
    required this.time,
    required this.pixelsPerSecond,
    required this.playheadFraction,
    required this.midiMin,
    required this.midiMax,
    this.confidenceThreshold = 0.6,
    this.rmsThreshold = 0.02,
    this.maxGapSec = 0.2,
    this.debugLogMapping = false,
    Color? glowColor,
    Color? coreColor,
  })  : glowColor = glowColor ?? Colors.white,
        coreColor = coreColor ?? Colors.white,
        super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) {
    if (frames.isEmpty) return;
    final currentTime = time.value;
    final playheadX = size.width * playheadFraction;
    final leftTime = currentTime - (playheadX / pixelsPerSecond);
    final rightTime = currentTime + ((size.width - playheadX) / pixelsPerSecond);

    double? firstMidi;
    double? lastMidi;
    if (debugLogMapping && kDebugMode && _loggedContourPainters.add(identityHashCode(this))) {
      for (final f in frames) {
        final midi = f.midi ?? (f.hz != null ? PitchMath.hzToMidi(f.hz!) : null);
        if (midi == null) continue;
        firstMidi ??= midi;
        lastMidi = midi;
      }
      if (firstMidi != null && lastMidi != null) {
        debugPrint(
          'CONTOUR RANGE: firstMidi=${firstMidi!.toStringAsFixed(2)} '
          'lastMidi=${lastMidi!.toStringAsFixed(2)}',
        );
      }
    }

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = glowColor.withOpacity(0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = coreColor.withOpacity(0.85);

    final path = Path();
    bool hasStarted = false;
    double? lastTime;
    var sampleIndex = 0;
    for (final f in frames) {
      if (f.time < leftTime) continue;
      if (f.time > rightTime) break;
      final hz = f.hz ?? 0.0;
      if (hz <= 0) {
        hasStarted = false;
        lastTime = null;
        continue;
      }
      if ((f.voicedProb ?? 1.0) < confidenceThreshold) {
        hasStarted = false;
        lastTime = null;
        continue;
      }
      if ((f.rms ?? 1.0) < rmsThreshold) {
        hasStarted = false;
        lastTime = null;
        continue;
      }
      if (lastTime != null && (f.time - lastTime!) > maxGapSec) {
        hasStarted = false;
      }
      final midi = f.midi ?? PitchMath.hzToMidi(hz);
      if (debugLogMapping && kDebugMode) {
        assert(midi > 0 && midi < 127);
      }
      final x = playheadX + (f.time - currentTime) * pixelsPerSecond;
      final y = PitchMath.midiToY(
        midi: midi,
        height: size.height,
        midiMin: midiMin,
        midiMax: midiMax,
      );
      if (debugLogMapping && kDebugMode && sampleIndex % 20 == 0) {
        debugPrint(
          'CONTOUR Y: timeMs=${(f.time * 1000).round()} '
          'midi=${midi.toStringAsFixed(2)} y=${y.toStringAsFixed(2)}',
        );
      }
      if (!hasStarted) {
        path.moveTo(x, y);
        hasStarted = true;
      } else {
        path.lineTo(x, y);
      }
      lastTime = f.time;
      sampleIndex += 1;
    }
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, corePaint);
  }

  @override
  bool shouldRepaint(covariant PitchContourPainter oldDelegate) {
    return oldDelegate.frames != frames ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.playheadFraction != playheadFraction ||
        oldDelegate.midiMin != midiMin ||
        oldDelegate.midiMax != midiMax ||
        oldDelegate.confidenceThreshold != confidenceThreshold ||
        oldDelegate.rmsThreshold != rmsThreshold ||
        oldDelegate.maxGapSec != maxGapSec;
  }
}
