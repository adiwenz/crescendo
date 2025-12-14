import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/exercise_note.dart';

enum NoteStatus { pending, good, near, off }

class StaffExerciseView extends StatelessWidget {
  final List<ExerciseNote> notes;
  final ValueListenable<int> currentIndex;
  final ValueListenable<double?> pitchMidi;
  final List<NoteStatus> statuses;
  final double gapPixels;
  final int midiCenter;

  const StaffExerciseView({
    super.key,
    required this.notes,
    required this.currentIndex,
    required this.pitchMidi,
    required this.statuses,
    this.gapPixels = 40,
    this.midiCenter = 60,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: CustomPaint(
        painter: _StaffPainter(
          notes: notes,
          currentIndex: currentIndex,
          pitchMidi: pitchMidi,
          statuses: statuses,
          gapPixels: gapPixels,
          midiCenter: midiCenter,
        ),
      ),
    );
  }
}

class _StaffPainter extends CustomPainter {
  final List<ExerciseNote> notes;
  final ValueListenable<int> currentIndex;
  final ValueListenable<double?> pitchMidi;
  final List<NoteStatus> statuses;
  final double gapPixels;
  final int midiCenter;
  _StaffPainter({
    required this.notes,
    required this.currentIndex,
    required this.pitchMidi,
    required this.statuses,
    required this.gapPixels,
    required this.midiCenter,
  }) : super(repaint: Listenable.merge([currentIndex, pitchMidi]));

  static const double lineSpacing = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final staffHeight = lineSpacing * 4;
    final staffTop = size.height / 2 - staffHeight / 2;
    final staffPaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1.2;

    for (var i = 0; i < 5; i++) {
      final y = staffTop + i * lineSpacing;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), staffPaint);
    }

    final noteSpacing = gapPixels;
    final headRadius = 8.0;
    for (var i = 0; i < notes.length; i++) {
      final note = notes[i];
      final x = noteSpacing / 2 + i * noteSpacing;
      final y = _midiToY(note.midi.toDouble(), staffTop + staffHeight / 2);

      // Ledger lines if above/below staff
      final stepsFromCenter = ((midiCenter - note.midi) / 1).round();
      final staffBottom = staffTop + lineSpacing * 4;
      if (y < staffTop) {
        for (double ly = staffTop; ly >= y; ly -= lineSpacing) {
          canvas.drawLine(Offset(x - headRadius, ly), Offset(x + headRadius, ly), staffPaint);
        }
      } else if (y > staffBottom) {
        for (double ly = staffBottom; ly <= y; ly += lineSpacing) {
          canvas.drawLine(Offset(x - headRadius, ly), Offset(x + headRadius, ly), staffPaint);
        }
      }

      final isCurrent = i == currentIndex.value;
      if (isCurrent) {
        final highlight = Paint()..color = Colors.lightBlueAccent.withOpacity(0.2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(x, y), width: 30, height: 30),
            const Radius.circular(8),
          ),
          highlight,
        );
      }

      final basePaint = Paint()..color = Colors.black87;
      canvas.drawCircle(Offset(x, y), headRadius, basePaint);

      // Status dot under note
      final status = statuses[i];
      Color statusColor;
      switch (status) {
        case NoteStatus.good:
          statusColor = Colors.green;
          break;
        case NoteStatus.near:
          statusColor = Colors.orange;
          break;
        case NoteStatus.off:
          statusColor = Colors.red;
          break;
        default:
          statusColor = Colors.grey.shade300;
      }
      if (status != NoteStatus.pending) {
        canvas.drawCircle(Offset(x, staffTop + staffHeight + 14), 5, Paint()..color = statusColor);
      }

      // Optional solfege label
      if (note.solfege != null) {
        final tp = TextPainter(
          text: TextSpan(text: note.solfege, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, y + headRadius + 4));
      }
    }

    // Pitch overlay at current note x
    final pitch = pitchMidi.value;
    if (pitch != null && currentIndex.value < notes.length) {
      final x = noteSpacing / 2 + currentIndex.value * noteSpacing;
      final y = _midiToY(pitch, staffTop + staffHeight / 2);
      final paint = Paint()..color = Colors.teal;
      canvas.drawCircle(Offset(x, y), 7, paint);
      canvas.drawLine(Offset(x, y - 14), Offset(x, y + 14), paint..strokeWidth = 2);
    }
  }

  double _midiToY(double midi, double centerY) {
    final diff = midi - midiCenter;
    return centerY - diff * (lineSpacing / 2);
  }

  @override
  bool shouldRepaint(covariant _StaffPainter oldDelegate) => true;
}
