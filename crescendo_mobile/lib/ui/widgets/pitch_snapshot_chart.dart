import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/replay_models.dart';

class PitchSnapshotChart extends StatelessWidget {
  final List<TargetNote> targetNotes;
  final List<PitchSample> recordedSamples;
  final int durationMs;
  final double height;

  const PitchSnapshotChart({
    super.key,
    required this.targetNotes,
    required this.recordedSamples,
    required this.durationMs,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = _normalizeSamplesToMs(recordedSamples, targetNotes);
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final domain = _computeTimeDomain(normalized, targetNotes);
          final minMax = _computeViewport(targetNotes, recordedSamples);
          return CustomPaint(
            painter: _SnapshotPainter(
              notes: targetNotes,
              samples: normalized,
              domainStartMs: domain.$1,
              domainDurationMs: domain.$2,
              minMidi: minMax.$1,
              maxMidi: minMax.$2,
              width: width,
              height: height,
            ),
          );
        },
      ),
    );
  }
}

class PitchSnapshotView extends StatelessWidget {
  final List<TargetNote> targetNotes;
  final List<PitchSample> pitchSamples;
  final int durationMs;
  final double height;

  const PitchSnapshotView({
    super.key,
    required this.targetNotes,
    required this.pitchSamples,
    required this.durationMs,
    this.height = 240,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = _normalizeSamplesToMs(pitchSamples, targetNotes);
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
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final offsetMs = _computeNoteStartOffsetMs(normalized, targetNotes);
            
            // Dynamic start time to avoid whitespace for sliced exercises
            var startMs = 0;
            if (targetNotes.isNotEmpty || normalized.isNotEmpty) {
              var minTv = 999999999;
              if (targetNotes.isNotEmpty) {
                final noteStart = _firstNoteMs(targetNotes) + offsetMs;
                if (noteStart < minTv) minTv = noteStart;
              }
              if (normalized.isNotEmpty) {
                final sampleStart = _firstSampleMs(normalized);
                if (sampleStart < minTv) minTv = sampleStart;
              }
              // If we found a valid start time > 0, use it (with padding)
              if (minTv < 999999999) {
                 startMs = math.max(0, minTv - 500); // 500ms lead-in padding
              }
            }

            final domainEndMs = _computeDomainEndMs(durationMs, normalized, targetNotes, offsetMs);
            final domain = (startMs, domainEndMs);
            final minMax = _computeViewport(targetNotes, pitchSamples);
            final minMidi = minMax.$1;
            final maxMidi = minMax.$2;
            const topPad = 8.0;
            const bottomPad = 8.0;
            assert(() {
              debugPrint(
                '[Snapshot] offsetMs=$offsetMs '
                'firstNoteMs=${_firstNoteMs(targetNotes)} '
                'firstContourMs=${_firstSampleMs(normalized)} '
                'domainEndMs=$domainEndMs',
              );
              debugPrint(
                'SNAPSHOT DOMAIN: startMs=${domain.$1} endMs=${domain.$2} '
                'durationMs=${domain.$2 - domain.$1}',
              );
              if (normalized.isNotEmpty) {
                final sampleTimes = normalized.map((s) => s.timeMs).toList();
                debugPrint(
                  'SNAPSHOT SAMPLES: ${sampleTimes.first}..${sampleTimes.last}',
                );
              }
              if (targetNotes.isNotEmpty) {
                debugPrint(
                  'SNAPSHOT NOTES: ${targetNotes.first.startMs}..${targetNotes.last.endMs}',
                );
              }
              return true;
            }());
            return Stack(
              children: [
                CustomPaint(
                  size: Size(width, height),
                  painter: _SnapshotGridPainter(
                    samples: normalized,
                    domainStartMs: domain.$1,
                    domainDurationMs: domain.$2 - domain.$1,
                    minMidi: minMidi,
                    maxMidi: maxMidi,
                    topPad: topPad,
                    bottomPad: bottomPad,
                    notes: targetNotes,
                    noteStartOffsetMs: offsetMs,
                  ),
                ),
                for (final note in targetNotes)
                  _NoteBubble(
                    note: note,
                    domainStartMs: domain.$1,
                    domainDurationMs: domain.$2 - domain.$1,
                    noteStartOffsetMs: offsetMs,
                    minMidi: minMidi,
                    maxMidi: maxMidi,
                    width: width,
                    height: height,
                    topPad: topPad,
                    bottomPad: bottomPad,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SnapshotPainter extends CustomPainter {
  final List<TargetNote> notes;
  final List<PitchSample> samples;
  final int domainStartMs;
  final int domainDurationMs;
  final double minMidi;
  final double maxMidi;
  final double width;
  final double height;

  _SnapshotPainter({
    required this.notes,
    required this.samples,
    required this.domainStartMs,
    required this.domainDurationMs,
    required this.minMidi,
    required this.maxMidi,
    required this.width,
    required this.height,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE6EEF3)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final midi = minMidi + (maxMidi - minMidi) * (i / 4);
      final y = _midiToY(midi, minMidi, maxMidi, size.height, 8, 8);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final path = Path();
    bool started = false;
    for (final s in _validSamplesForSnapshot(samples)) {
      final x = _timeToX(s.timeMs, size.width, domainStartMs, domainDurationMs);
      final y = _midiToY(s.midi!, minMidi, maxMidi, size.height, 8, 8);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    final contourPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFFFB347);
    canvas.drawPath(path, contourPaint);

    final notePaint = Paint()..color = const Color(0xFFFFC978);
    const barHeight = 14.0;
    for (final n in notes) {
      final midMs = ((n.startMs + n.endMs) / 2).round();
      final x = _timeToX(midMs, size.width, domainStartMs, domainDurationMs);
      final y = _midiToY(n.midi, minMidi, maxMidi, size.height, 8, 8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y), width: 36, height: barHeight),
          const Radius.circular(7),
        ),
        notePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SnapshotPainter oldDelegate) {
    return oldDelegate.notes != notes ||
        oldDelegate.samples != samples ||
        oldDelegate.domainStartMs != domainStartMs ||
        oldDelegate.domainDurationMs != domainDurationMs ||
        oldDelegate.minMidi != minMidi ||
        oldDelegate.maxMidi != maxMidi;
  }
}

class _SnapshotGridPainter extends CustomPainter {
  final List<PitchSample> samples;
  final int domainStartMs;
  final int domainDurationMs;
  final double minMidi;
  final double maxMidi;
  final double topPad;
  final double bottomPad;
  final List<TargetNote> notes;
  final int noteStartOffsetMs;

  _SnapshotGridPainter({
    required this.samples,
    required this.domainStartMs,
    required this.domainDurationMs,
    required this.minMidi,
    required this.maxMidi,
    required this.topPad,
    required this.bottomPad,
    required this.notes,
    required this.noteStartOffsetMs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE6EEF3)
      ..strokeWidth = 1;
    for (var i = 0; i <= 6; i++) {
      final midi = minMidi + (maxMidi - minMidi) * (i / 6);
      final y = _midiToY(midi, minMidi, maxMidi, size.height, topPad, bottomPad);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final rightEdge = Paint()
      ..color = const Color(0xFFDEE6EC)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(size.width - 1, 0),
      Offset(size.width - 1, size.height),
      rightEdge,
    );

    final path = Path();
    bool started = false;
    for (final s in _validSamplesForSnapshot(samples)) {
      final x = _timeToX(s.timeMs, size.width, domainStartMs, domainDurationMs);
      final y = _midiToY(s.midi!, minMidi, maxMidi, size.height, topPad, bottomPad);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    final contourPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFFFB347);
    canvas.drawPath(path, contourPaint);

    if (kDebugMode && notes.isNotEmpty) {
      final tickPaint = Paint()
        ..color = const Color(0xFFC7D1D8)
        ..strokeWidth = 1;
      final dotPaint = Paint()..color = const Color(0x99FFB347);
      for (final n in notes) {
        final shiftedStart = n.startMs + noteStartOffsetMs;
        final shiftedEnd = n.endMs + noteStartOffsetMs;
        final midMs = ((shiftedStart + shiftedEnd) / 2).round();
        final x = _timeToX(midMs, size.width, domainStartMs, domainDurationMs);
        canvas.drawLine(Offset(x, size.height - 12), Offset(x, size.height), tickPaint);
        final closest = _closestSample(samples, midMs);
        if (closest != null) {
          final y = _midiToY(
            closest.midi ?? _hzToMidiStatic(closest.freqHz) ?? minMidi,
            minMidi,
            maxMidi,
            size.height,
            topPad,
            bottomPad,
          );
          canvas.drawCircle(Offset(x, y), 3, dotPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SnapshotGridPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.domainStartMs != domainStartMs ||
        oldDelegate.domainDurationMs != domainDurationMs ||
        oldDelegate.minMidi != minMidi ||
        oldDelegate.maxMidi != maxMidi ||
        oldDelegate.topPad != topPad ||
        oldDelegate.bottomPad != bottomPad ||
        oldDelegate.notes != notes ||
        oldDelegate.noteStartOffsetMs != noteStartOffsetMs;
  }
}

class _NoteBubble extends StatelessWidget {
  final TargetNote note;
  final int domainStartMs;
  final int domainDurationMs;
  final int noteStartOffsetMs;
  final double minMidi;
  final double maxMidi;
  final double width;
  final double height;
  final double topPad;
  final double bottomPad;

  const _NoteBubble({
    required this.note,
    required this.domainStartMs,
    required this.domainDurationMs,
    required this.noteStartOffsetMs,
    required this.minMidi,
    required this.maxMidi,
    required this.width,
    required this.height,
    required this.topPad,
    required this.bottomPad,
  });

  @override
  Widget build(BuildContext context) {
    const pillHeight = 8.0;
    final shiftedStart = note.startMs + noteStartOffsetMs;
    final shiftedEnd = note.endMs + noteStartOffsetMs;
    final midMs = ((shiftedStart + shiftedEnd) / 2).round();
    final x = _timeToX(midMs, width, domainStartMs, domainDurationMs);
    final y = _midiToY(note.midi, minMidi, maxMidi, height, topPad, bottomPad);
    final spanMs = (shiftedEnd - shiftedStart).clamp(1, domainDurationMs);
    final spanPx = (spanMs / domainDurationMs) * width;
    final pillWidth = spanPx.clamp(24.0, 48.0);
    var left = x - pillWidth / 2;
    var top = y - pillHeight / 2;
    left = left.clamp(0.0, width - pillWidth);
    top = top.clamp(0.0, height - pillHeight);

    return Positioned(
      left: left,
      top: top,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: pillWidth,
            height: pillHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD6A1),
              borderRadius: BorderRadius.circular(3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

(double, double) _computeViewport(
  List<TargetNote> notes,
  List<PitchSample> samples,
) {
  final noteMidis = notes.map((n) => n.midi).toList();
  final sampleMidis = samples
      .map((s) => s.midi ?? _hzToMidiStatic(s.freqHz))
      .whereType<double>()
      .toList();
  final source = noteMidis.isNotEmpty ? noteMidis : sampleMidis;
  if (source.isEmpty) return (48, 72);
  final min = source.reduce(math.min) - 3;
  final max = source.reduce(math.max) + 3;
  return (min, max);
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

double _timeToX(int timeMs, double width, int domainStartMs, int domainDurationMs) {
  if (domainDurationMs <= 0) return 0;
  final t = (timeMs - domainStartMs) / domainDurationMs;
  final clamped = t.clamp(0.0, 1.0);
  return clamped * width;
}

List<PitchSample> _validSamplesForSnapshot(List<PitchSample> samples) {
  return samples.where((s) {
    final midi = s.midi ?? _hzToMidiStatic(s.freqHz);
    return midi != null && midi.isFinite;
  }).map((s) {
    final midi = s.midi ?? _hzToMidiStatic(s.freqHz);
    return PitchSample(timeMs: s.timeMs, midi: midi);
  }).toList();
}

PitchSample? _closestSample(List<PitchSample> samples, int targetMs) {
  if (samples.isEmpty) return null;
  PitchSample? closest;
  var bestDelta = 999999;
  for (final s in samples) {
    final delta = (s.timeMs - targetMs).abs();
    if (delta < bestDelta) {
      bestDelta = delta;
      closest = s;
    }
  }
  if (bestDelta > 200) return null;
  return closest;
}

double? _hzToMidiStatic(double? hz) {
  if (hz == null || hz <= 0 || hz.isNaN || hz.isInfinite) return null;
  return 69 + 12 * (math.log(hz / 440.0) / math.ln2);
}

(int, int) _computeTimeDomain(
  List<PitchSample> samples,
  List<TargetNote> notes,
) {
  var startMs = 0;
  var endMs = 0;
  if (samples.isNotEmpty) {
    startMs = samples.first.timeMs;
    endMs = samples.last.timeMs;
  } else if (notes.isNotEmpty) {
    startMs = notes.first.startMs;
    endMs = notes.first.endMs;
  }
  if (samples.isNotEmpty) {
    for (final s in samples) {
      if (s.timeMs < startMs) startMs = s.timeMs;
      if (s.timeMs > endMs) endMs = s.timeMs;
    }
  }
  if (notes.isNotEmpty) {
    var minNoteStart = notes.first.startMs;
    var maxNoteEnd = notes.first.endMs;
    for (final n in notes) {
      if (n.startMs < minNoteStart) minNoteStart = n.startMs;
      if (n.endMs > maxNoteEnd) maxNoteEnd = n.endMs;
    }
    startMs = math.min(startMs, minNoteStart);
    endMs = math.max(endMs, maxNoteEnd);
  }
  final duration = math.max(1, endMs - startMs);
  return (startMs, duration);
}

List<PitchSample> _normalizeSamplesToMs(
  List<PitchSample> samples,
  List<TargetNote> notes,
) {
  if (samples.isEmpty) return samples;
  var maxSample = samples.first.timeMs;
  for (final s in samples) {
    if (s.timeMs > maxSample) maxSample = s.timeMs;
  }
  var maxNote = 0;
  for (final n in notes) {
    if (n.endMs > maxNote) maxNote = n.endMs;
  }
  if (maxSample < 1000 && maxNote > 1000) {
    if (kDebugMode) {
      debugPrint(
        'SNAPSHOT TIME NORMALIZE: sample max=$maxSample note max=$maxNote (seconds->ms)',
      );
    }
    return samples
        .map((s) => PitchSample(timeMs: s.timeMs * 1000, midi: s.midi, freqHz: s.freqHz))
        .toList();
  }
  return samples;
}

int _computeNoteStartOffsetMs(
  List<PitchSample> samples,
  List<TargetNote> notes,
) {
  if (notes.isEmpty) return 0;
  const fixedPrerollMs = 2000;
  return fixedPrerollMs;
}

int _computeDomainEndMs(
  int durationMs,
  List<PitchSample> samples,
  List<TargetNote> notes,
  int noteStartOffsetMs,
) {
  var endMs = durationMs;
  final sampleMax = _lastSampleMs(samples);
  if (sampleMax > endMs) endMs = sampleMax;
  final noteMax = _lastNoteMs(notes);
  if (noteMax + noteStartOffsetMs > endMs) endMs = noteMax + noteStartOffsetMs;
  return endMs <= 0 ? 1 : endMs;
}

int _firstNoteMs(List<TargetNote> notes) {
  if (notes.isEmpty) return 0;
  var minMs = notes.first.startMs;
  for (final n in notes) {
    if (n.startMs < minMs) minMs = n.startMs;
  }
  return minMs;
}

int _lastNoteMs(List<TargetNote> notes) {
  if (notes.isEmpty) return 0;
  var maxMs = notes.first.endMs;
  for (final n in notes) {
    if (n.endMs > maxMs) maxMs = n.endMs;
  }
  return maxMs;
}

int _firstSampleMs(List<PitchSample> samples) {
  if (samples.isEmpty) return 0;
  var minMs = samples.first.timeMs;
  for (final s in samples) {
    if (s.timeMs < minMs) minMs = s.timeMs;
  }
  return minMs;
}

int _lastSampleMs(List<PitchSample> samples) {
  if (samples.isEmpty) return 0;
  var maxMs = samples.first.timeMs;
  for (final s in samples) {
    if (s.timeMs > maxMs) maxMs = s.timeMs;
  }
  return maxMs;
}
