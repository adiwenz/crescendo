import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/pitch_frame.dart';
import '../../models/reference_note.dart';
import '../../models/siren_path.dart';
import '../../utils/pitch_math.dart';
import '../../utils/pitch_tail_buffer.dart';
import '../theme/app_theme.dart';

enum PitchMatch { good, near, off }

final Set<int> _loggedNoteMappingPainters = <int>{};
int? _lastLoggedRunId; // Track last logged runId for painter logging
int?
    _lastFirstNoteAlignmentLogRunId; // Track if we've logged first note alignment

class PitchHighwayPainter extends CustomPainter {
  final List<ReferenceNote> notes;
  final List<PitchFrame> pitchTail;
  final ValueListenable<double> time;
  final double pixelsPerSecond;
  final double playheadFraction;
  final double smoothingWindowSec;
  final bool? drawBackground;
  final bool showLivePitch;
  final bool showPlayheadLine;
  final int midiMin;
  final int midiMax;
  final AppThemeColors colors;
  final ValueListenable<double?>? liveMidi;
  final double pitchTailTimeOffsetSec;
  final double noteTimeOffsetSec;
  final List<TailPoint>? tailPoints;
  final bool debugLogMapping;
  final int? runId; // For debugging: track which run this painter belongs to
  final SirenPath?
      sirenPath; // Optional visual path for Sirens (separate from audio notes)

  PitchHighwayPainter({
    required this.notes,
    required this.pitchTail,
    required this.time,
    this.sirenPath,
    this.pixelsPerSecond = 160,
    this.playheadFraction = 0.45,
    this.smoothingWindowSec = 0.2,
    this.drawBackground = true,
    this.showLivePitch = true,
    this.showPlayheadLine = true,
    this.midiMin = 48,
    this.midiMax = 72,
    this.liveMidi,
    this.pitchTailTimeOffsetSec = 0,
    this.noteTimeOffsetSec = 0,
    this.tailPoints,
    this.debugLogMapping = false,
    this.runId,
    AppThemeColors? colors,
  })  : colors = colors ?? AppThemeColors.dark,
        // CRITICAL: Always use time as repaint listenable for stability.
        // liveMidi.value is read directly in paint() method, so repaints happen on time ticks anyway.
        super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) {
    // Log painter input once per runId (debugging instrumentation)
    if (runId != null && _lastLoggedRunId != runId) {
      _lastLoggedRunId = runId;
      final pitchPointsCount = pitchTail.length;
      final tailPointsCount = tailPoints?.length ?? 0;
      debugPrint('[Painter] runId=$runId '
          'pitchPoints=$pitchPointsCount '
          'tailPoints=$tailPointsCount '
          'notes=${notes.length} '
          'time=${time.value}');
    }

    // Use time.value directly - notes already have absolute times including lead-in
    // At time.value=0, notes with startSec=2.0 will be positioned 2 seconds to the right
    // As time.value increases, notes slide left toward the playhead
    final currentTime = time.value;
    if (drawBackground ?? true) {
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
    }

    final gridPaint = Paint()
      ..color = colors.divider
          .withOpacity(colors.isMagical ? 0.18 : (colors.isDark ? 1 : 0.6))
      ..strokeWidth = 1;
    final gridStep = math.max(1, (midiMax - midiMin) ~/ 6);
    for (var midi = midiMin; midi <= midiMax; midi += gridStep) {
      final y = PitchMath.midiToY(
        midi: midi.toDouble(),
        height: size.height,
        midiMin: midiMin,
        midiMax: midiMax,
      );
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final playheadX = size.width * playheadFraction;
    final noteColor = colors.isMagical
        ? colors.accentPurple.withOpacity(0.65)
        : (colors.isDark
            ? colors.textPrimary.withOpacity(0.55)
            : colors.accentPurple.withOpacity(0.55));
    final barHeight = 16.0;
    final radius = Radius.circular(barHeight);
    final currentNote = _noteAtTime(currentTime);
    final smoothedMidi = liveMidi?.value ?? _smoothedMidiAt(currentTime);
    final currentStatus = _statusForTime(currentTime, smoothedMidi);

    if (debugLogMapping &&
        kDebugMode &&
        _loggedNoteMappingPainters.add(identityHashCode(this))) {
      assert(midiMax > midiMin);
      for (var i = 0; i < math.min(3, notes.length); i++) {
        final n = notes[i];
        assert(n.midi > 0 && n.midi < 127);
        final y = PitchMath.midiToY(
          midi: n.midi.toDouble(),
          height: size.height,
          midiMin: midiMin,
          midiMax: midiMax,
        );
        debugPrint(
          'NOTE Y: label=${n.lyric ?? ''} midi=${n.midi.toStringAsFixed(2)} '
          'y=${y.toStringAsFixed(2)}',
        );
        debugPrint(
          'NOTE PILL TOP: label=${n.lyric ?? ''} '
          'pillTop=${(y - barHeight / 2).toStringAsFixed(2)} '
          'pillHeight=$barHeight',
        );
      }
    }

    // First pass: draw Sirens visual path if provided (separate from audio notes)
    if (sirenPath != null && sirenPath!.points.isNotEmpty) {
      // Draw Sirens as separate bell curves for each cycle (no connection between cycles)
      final sirenPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = noteColor;

      final sirenGlowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = (colors.isMagical ? colors.lavenderGlow : colors.glow)
            .withOpacity(colors.isMagical ? 0.4 : 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

      // Group points into cycles by detecting time gaps (> 1 second gap = new cycle)
      final cycleSegments = <List<Offset>>[];
      List<Offset>? currentSegment;
      double? lastTimeSec;
      const gapThresholdSec = 1.0; // If gap > 1s, start a new segment

      for (final point in sirenPath!.points) {
        final x = playheadX + (point.tSec - currentTime) * pixelsPerSecond;
        // Skip points outside visible area
        if (x < -32 || x > size.width + 32) {
          lastTimeSec = point.tSec;
          continue;
        }

        final y = PitchMath.midiToY(
          midi: point.midiFloat,
          height: size.height,
          midiMin: midiMin,
          midiMax: midiMax,
        );

        // Check if this point starts a new cycle (large time gap from previous)
        if (lastTimeSec != null &&
            (point.tSec - lastTimeSec) > gapThresholdSec) {
          // Save current segment and start a new one
          if (currentSegment != null && currentSegment.length >= 2) {
            cycleSegments.add(currentSegment);
          }
          currentSegment = [Offset(x, y)];
        } else {
          // Continue current segment
          currentSegment ??= [];
          currentSegment.add(Offset(x, y));
        }

        lastTimeSec = point.tSec;
      }

      // Add final segment
      if (currentSegment != null && currentSegment.length >= 2) {
        cycleSegments.add(currentSegment);
      }

      // Draw each cycle segment as a separate path
      for (final segment in cycleSegments) {
        if (segment.length < 2) continue;

        final path = Path();
        path.moveTo(segment.first.dx, segment.first.dy);

        // Build smooth path through this segment's points
        for (var i = 1; i < segment.length; i++) {
          final prev = segment[i - 1];
          final curr = segment[i];

          if (i == 1) {
            // First segment: use midpoint for smooth start
            final midX = (prev.dx + curr.dx) / 2;
            final midY = (prev.dy + curr.dy) / 2;
            path.quadraticBezierTo(prev.dx, prev.dy, midX, midY);
          } else if (i == segment.length - 1) {
            // Last segment: use midpoint for smooth end
            final prevPrev = segment[i - 2];
            final midX = (prevPrev.dx + prev.dx) / 2;
            final midY = (prevPrev.dy + prev.dy) / 2;
            path.quadraticBezierTo(midX, midY, curr.dx, curr.dy);
          } else {
            // Middle segments: use midpoint smoothing
            final prevPrev = segment[i - 2];
            final controlX = (prevPrev.dx + prev.dx) / 2;
            final controlY = (prevPrev.dy + prev.dy) / 2;
            path.quadraticBezierTo(controlX, controlY, curr.dx, curr.dy);
          }
        }

        canvas.drawPath(path, sirenGlowPaint);
        canvas.drawPath(path, sirenPaint);
      }

      // Skip all notes in regular rendering (Sirens uses visual path only)
      // Audio notes are still used for pitch detection matching
    } else {
      // Original glide rendering for non-Sirens exercises
      for (var i = 0; i < notes.length; i++) {
        final n = notes[i];
        if (n.isGlideStart && n.glideEndMidi != null) {
          // Find the corresponding glide end note
          ReferenceNote? glideEnd;
          for (var j = i + 1; j < notes.length; j++) {
            if (notes[j].isGlideEnd && notes[j].midi == n.glideEndMidi) {
              glideEnd = notes[j];
              break;
            }
          }

          if (glideEnd != null) {
            // Skip glides during lead-in
            if (n.startSec < 2.0) continue;

            // Draw continuous curve between start and end
            final startX =
                playheadX + (n.startSec - currentTime) * pixelsPerSecond;
            final endX =
                playheadX + (glideEnd.endSec - currentTime) * pixelsPerSecond;

            if (endX < -32 || startX > size.width + 32) continue;

            final startY = PitchMath.midiToY(
              midi: n.midi.toDouble(),
              height: size.height,
              midiMin: midiMin,
              midiMax: midiMax,
            );
            final endY = PitchMath.midiToY(
              midi: glideEnd.midi.toDouble(),
              height: size.height,
              midiMin: midiMin,
              midiMax: midiMax,
            );

            // Draw glide curve as a smooth path
            final glidePath = Path();
            glidePath.moveTo(startX, startY);

            // Use a cubic bezier for smooth curve (control points create smooth interpolation)
            final controlPoint1X = startX + (endX - startX) * 0.33;
            final controlPoint2X = startX + (endX - startX) * 0.67;
            glidePath.cubicTo(
              controlPoint1X,
              startY,
              controlPoint2X,
              endY,
              endX,
              endY,
            );

            final glidePaint = Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.0
              ..strokeCap = StrokeCap.round
              ..color = noteColor;

            final glowPaint = Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6.0
              ..strokeCap = StrokeCap.round
              ..color = (colors.isMagical ? colors.lavenderGlow : colors.glow)
                  .withOpacity(colors.isMagical ? 0.4 : 0.3)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

            canvas.drawPath(glidePath, glowPaint);
            canvas.drawPath(glidePath, glidePaint);

            // Draw small endpoint markers
            final endpointRadius = 4.0;
            canvas.drawCircle(
                Offset(startX, startY), endpointRadius, glidePaint);
            canvas.drawCircle(Offset(endX, endY), endpointRadius, glidePaint);

            // Skip the glide end note in the regular loop
            continue;
          }
        }

        // Skip glide endpoints (they're handled above)
        if (n.isGlideEnd) continue;

        // Regular note rendering (non-glide notes)
        // Skip notes during lead-in (leadInSec = 2.0s)
        // Pattern notes are built with: startSec = leadInSec + patternStartSec + xStart
        // For first pattern (k=0): patternStartSec = 2.0, so first note has startSec = 2.0 + 0.0 = 2.0
        // This check (< 2.0) skips notes BEFORE lead-in ends, but allows notes AT 2.0 (first note)
        if (n.startSec < 2.0) continue;

        final startX = playheadX + (n.startSec - currentTime) * pixelsPerSecond;
        final endX = playheadX + (n.endSec - currentTime) * pixelsPerSecond;

        // Debug: Log alignment when first note crosses playline
        if (runId != null &&
            i == 0 &&
            _lastFirstNoteAlignmentLogRunId != runId &&
            (currentTime - n.startSec).abs() < 0.05) {
          final diffPx = startX - playheadX;
          debugPrint(
              '[NoteAlign] First note alignment: runId=$runId, currentTime=${currentTime.toStringAsFixed(3)}, noteStartSec=${n.startSec.toStringAsFixed(3)}, startX=${startX.toStringAsFixed(1)}, playlineX=${playheadX.toStringAsFixed(1)}, diffPx=${diffPx.toStringAsFixed(1)}');
          _lastFirstNoteAlignmentLogRunId = runId;
        }
        if (endX < -32 || startX > size.width + 32) continue;
        final y = PitchMath.midiToY(
          midi: n.midi.toDouble(),
          height: size.height,
          midiMin: midiMin,
          midiMax: midiMax,
        );
        final rect = RRect.fromLTRBR(
          startX,
          y - barHeight / 2,
          endX,
          y + barHeight / 2,
          radius,
        );
        final Color barColor;
        if (identical(n, currentNote)) {
          if (colors.isDark) {
            barColor = switch (currentStatus) {
              PitchMatch.good => colors.textPrimary.withOpacity(0.95),
              PitchMatch.near => colors.textPrimary.withOpacity(0.8),
              PitchMatch.off => colors.textPrimary.withOpacity(0.6),
            };
          } else {
            barColor = switch (currentStatus) {
              PitchMatch.good => colors.accentPurple.withOpacity(0.95),
              PitchMatch.near => colors.accentPurple.withOpacity(0.75),
              PitchMatch.off => colors.accentPurple.withOpacity(0.55),
            };
          }
        } else {
          barColor = noteColor;
        }
        final glowPaint = Paint()
          ..color = (colors.isMagical ? colors.lavenderGlow : colors.glow)
              .withOpacity(colors.isMagical ? 0.4 : 1)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        final paint = Paint()..color = barColor;
        canvas.drawRRect(rect, glowPaint);
        canvas.drawRRect(rect, paint);

        if (n.lyric != null && n.lyric!.isNotEmpty) {
          final tp = TextPainter(
            text: TextSpan(
              text: n.lyric,
              style: TextStyle(color: colors.textPrimary, fontSize: 12),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: math.max(0, endX - startX - 8));
          tp.paint(canvas, Offset(startX + 4, y - tp.height / 2));
        }
      }
    }

    if (showLivePitch) {
      if (tailPoints != null) {
        _drawTailPoints(canvas, size, currentTime, playheadX, tailPoints!);
      } else {
        _drawPitchTrail(canvas, size, currentTime, playheadX);
      }

      if (smoothedMidi != null) {
        assert(() {
          final tailList = tailPoints;
          if (tailList != null && tailList.isNotEmpty) {
            final tailY = tailList.last.yPx;
            final ballY = PitchMath.midiToY(
              midi: smoothedMidi,
              height: size.height,
              midiMin: midiMin,
              midiMax: midiMax,
            );
            return (tailY - ballY).abs() < 0.1;
          } else if (pitchTail.isNotEmpty) {
            final tailMidi = pitchTail.last.midi;
            if (tailMidi != null) {
              final tailY = PitchMath.midiToY(
                midi: tailMidi,
                height: size.height,
                midiMin: midiMin,
                midiMax: midiMax,
              );
              final ballY = PitchMath.midiToY(
                midi: smoothedMidi,
                height: size.height,
                midiMin: midiMin,
                midiMax: midiMax,
              );
              return (tailY - ballY).abs() < 0.1;
            }
          }
          return true;
        }());
        final y = PitchMath.midiToY(
          midi: smoothedMidi,
          height: size.height,
          midiMin: midiMin,
          midiMax: midiMax,
        );
        final head = Offset(playheadX, y);
        canvas.drawCircle(
          head,
          16,
          Paint()
            ..color = colors.glow
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
        );
        canvas.drawCircle(
          head,
          10,
          Paint()
            ..color = colors.textPrimary.withOpacity(0.5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        canvas.drawCircle(head, 7, Paint()..color = colors.textPrimary);
      }
    }

    if (showPlayheadLine) {
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.3)
        ..strokeWidth = 2.0;
      canvas.drawLine(
        Offset(playheadX + 0.5, 0),
        Offset(playheadX + 0.5, size.height),
        shadowPaint,
      );
      final playheadPaint = Paint()
        ..color = colors.accentBlue.withOpacity(0.7)
        ..strokeWidth = 2.0;
      canvas.drawLine(
          Offset(playheadX, 0), Offset(playheadX, size.height), playheadPaint);
    }
  }

  ReferenceNote? _noteAtTime(double t) {
    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];

      // Check if we're in a glide
      if (n.isGlideStart && n.glideEndMidi != null) {
        ReferenceNote? glideEnd;
        for (var j = i + 1; j < notes.length; j++) {
          if (notes[j].isGlideEnd && notes[j].midi == n.glideEndMidi) {
            glideEnd = notes[j];
            break;
          }
        }
        if (glideEnd != null && t >= n.startSec && t <= glideEnd.endSec) {
          // Interpolate MIDI value for the glide
          final progress = (t - n.startSec) / (glideEnd.endSec - n.startSec);
          final interpolatedMidi = n.midi + (glideEnd.midi - n.midi) * progress;
          // Return a virtual note with interpolated MIDI
          return ReferenceNote(
            startSec: n.startSec,
            endSec: glideEnd.endSec,
            midi: interpolatedMidi.round(),
            lyric: n.lyric,
          );
        }
      }

      // Regular note check
      if (t >= n.startSec && t <= n.endSec && !n.isGlideEnd) return n;
    }
    return null;
  }

  PitchMatch _statusForTime(double t, double? latestMidi) {
    if (latestMidi == null) return PitchMatch.off;
    final ref = _noteAtTime(t);
    if (ref == null) return PitchMatch.off;
    final cents = (latestMidi - ref.midi) * 100;
    final absCents = cents.abs();
    if (absCents <= 25) return PitchMatch.good;
    if (absCents <= 60) return PitchMatch.near;
    return PitchMatch.off;
  }

  double? _smoothedMidiAt(double t) {
    if (pitchTail.isEmpty) return null;
    if (smoothingWindowSec <= 0) return _latestMidiAtOrBefore(t);
    final start = t - smoothingWindowSec;
    double weightedSum = 0;
    double totalWeight = 0;
    for (final f in pitchTail) {
      final midi = f.midi;
      if (midi == null || f.time < start || f.time > t) continue;
      final age = t - f.time;
      final weight = 1 - (age / smoothingWindowSec);
      final eased = weight * weight;
      weightedSum += midi * eased;
      totalWeight += eased;
    }
    if (totalWeight == 0) return _latestMidiAtOrBefore(t);
    return weightedSum / totalWeight;
  }

  double? _latestMidiAtOrBefore(double t) {
    for (var i = pitchTail.length - 1; i >= 0; i--) {
      final f = pitchTail[i];
      if (f.midi != null && f.time <= t) return f.midi;
    }
    return null;
  }

  void _drawPitchTrail(Canvas canvas, Size size, double t, double playheadX) {
    if (pitchTail.isEmpty) return;
    final tAdjusted = t + pitchTailTimeOffsetSec;
    const trailWindowSec = 3.0;
    const maxJumpPx = 60.0;
    const maxGapSec = 0.12;
    const baseAlpha = 0.25;

    final raw = <_PitchSample>[];
    double? lastY;
    for (final f in pitchTail) {
      if (f.time < tAdjusted - trailWindowSec || f.time > tAdjusted) continue;
      final midi = f.midi;
      if (midi == null) continue;
      final y = PitchMath.midiToY(
        midi: midi,
        height: size.height,
        midiMin: midiMin,
        midiMax: midiMax,
      );
      if (lastY != null && (y - lastY).abs() > maxJumpPx) continue;
      lastY = y;
      final voiced = (f.voicedProb ?? 1.0) >= 0.6 && (f.rms ?? 1.0) >= 0.02;
      raw.add(_PitchSample(time: f.time, y: y, voiced: voiced));
    }
    if (raw.length < 2) {
      final live = liveMidi?.value;
      if (live == null) return;
      final y = PitchMath.midiToY(
        midi: live,
        height: size.height,
        midiMin: midiMin,
        midiMax: midiMax,
      );
      final shortTrailSec = 0.2;
      final startX = playheadX + (-shortTrailSec) * pixelsPerSecond;
      final endX = playheadX;
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = colors.textPrimary.withOpacity(0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      final corePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = colors.textPrimary.withOpacity(0.35);
      final path = Path()
        ..moveTo(startX, y)
        ..lineTo(endX, y);
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, corePaint);
      return;
    }

    if (raw.length < 2) return;

    for (var i = 1; i < raw.length; i++) {
      final prev = raw[i - 1];
      final curr = raw[i];
      if ((curr.time - prev.time) > maxGapSec) continue;
      final age = (tAdjusted - curr.time).clamp(0.0, trailWindowSec);
      final fade = 1 - (age / trailWindowSec);
      final base = (baseAlpha * fade).clamp(0.0, baseAlpha);
      if (base <= 0) continue;
      final voicedFactor = curr.voiced ? 1.0 : 0.35;
      final alpha = (base * voicedFactor).clamp(0.0, baseAlpha);
      final xPrev = playheadX + (prev.time - tAdjusted) * pixelsPerSecond;
      final xCurr = playheadX + (curr.time - tAdjusted) * pixelsPerSecond;
      if (xCurr < -16 || xPrev > size.width + 16) continue;
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = colors.textPrimary.withOpacity(alpha * 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      final corePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = colors.textPrimary.withOpacity(alpha);
      canvas.drawLine(Offset(xPrev, prev.y), Offset(xCurr, curr.y), glowPaint);
      canvas.drawLine(Offset(xPrev, prev.y), Offset(xCurr, curr.y), corePaint);
    }
  }

  void _drawTailPoints(
    Canvas canvas,
    Size size,
    double t,
    double playheadX,
    List<TailPoint> points,
  ) {
    if (points.length < 2) return;
    final tAdjusted = t + pitchTailTimeOffsetSec;
    const trailWindowSec = 3.0;
    const baseAlpha = 0.25;
    const maxGapSec = 0.12;

    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      if ((curr.tSec - prev.tSec) > maxGapSec) continue;
      final age = (tAdjusted - curr.tSec).clamp(0.0, trailWindowSec);
      final fade = 1 - (age / trailWindowSec);
      final base = (baseAlpha * fade).clamp(0.0, baseAlpha);
      if (base <= 0) continue;
      final voicedFactor = curr.voiced ? 1.0 : 0.35;
      final alpha = (base * voicedFactor).clamp(0.0, baseAlpha);
      final xPrev = playheadX + (prev.tSec - tAdjusted) * pixelsPerSecond;
      final xCurr = playheadX + (curr.tSec - tAdjusted) * pixelsPerSecond;
      if (xCurr < -16 || xPrev > size.width + 16) continue;
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = colors.textPrimary.withOpacity(alpha * 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      final corePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = colors.textPrimary.withOpacity(alpha);
      canvas.drawLine(
          Offset(xPrev, prev.yPx), Offset(xCurr, curr.yPx), glowPaint);
      canvas.drawLine(
          Offset(xPrev, prev.yPx), Offset(xCurr, curr.yPx), corePaint);
    }
  }

  @override
  bool shouldRepaint(covariant PitchHighwayPainter oldDelegate) {
    return oldDelegate.notes != notes ||
        oldDelegate.pitchTail != pitchTail ||
        oldDelegate.tailPoints != tailPoints ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.playheadFraction != playheadFraction ||
        (oldDelegate.drawBackground ?? true) != (drawBackground ?? true) ||
        oldDelegate.smoothingWindowSec != smoothingWindowSec ||
        oldDelegate.pitchTailTimeOffsetSec != pitchTailTimeOffsetSec ||
        oldDelegate.showLivePitch != showLivePitch ||
        oldDelegate.showPlayheadLine != showPlayheadLine;
  }
}

class _PitchSample {
  final double time;
  final double y;
  final bool voiced;

  const _PitchSample({
    required this.time,
    required this.y,
    required this.voiced,
  });
}
