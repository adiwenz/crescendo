import 'package:flutter/material.dart';

import '../../models/exercise_take.dart';

class ScoreLineChart extends StatelessWidget {
  final List<ExerciseTake> takes;
  const ScoreLineChart({super.key, required this.takes});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: CustomPaint(
        painter: _ScoreLinePainter(takes),
      ),
    );
  }
}

class _ScoreLinePainter extends CustomPainter {
  final List<ExerciseTake> takes;
  _ScoreLinePainter(this.takes);

  @override
  void paint(Canvas canvas, Size size) {
    if (takes.isEmpty) return;
    final bgPaint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.lightBlueAccent.withOpacity(0.15), Colors.white],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
      bgPaint,
    );

    final maxScore = 100.0;
    final minScore = takes.map((t) => t.score0to100).reduce((a, b) => a < b ? a : b);
    final yMin = (minScore - 10).clamp(0, 90);
    final dx = size.width / (takes.length - 1 == 0 ? 1 : takes.length - 1);
    final points = <Offset>[];
    for (var i = 0; i < takes.length; i++) {
      final x = dx * i;
      final score = takes[i].score0to100;
      final y = size.height - ((score - yMin) / (maxScore - yMin)) * size.height;
      points.add(Offset(x, y.clamp(0, size.height)));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    final glowPaint = Paint()
      ..color = Colors.blueAccent.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, glowPaint);

    final linePaint = Paint()
      ..color = Colors.blueAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 6, Paint()..color = Colors.white);
      canvas.drawCircle(points[i], 4, Paint()..color = Colors.blueAccent);
    }

    // highlight best
    final best = takes.reduce((a, b) => a.score0to100 >= b.score0to100 ? a : b);
    final bestIdx = takes.indexOf(best);
    final bestPt = points[bestIdx];
    canvas.drawCircle(bestPt, 10, Paint()..color = Colors.amber.withOpacity(0.25));
    canvas.drawCircle(bestPt, 6, Paint()..color = Colors.amber);
  }

  @override
  bool shouldRepaint(covariant _ScoreLinePainter oldDelegate) => oldDelegate.takes != takes;
}
