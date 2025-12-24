import 'package:flutter/material.dart';

class TimelineTrack extends CustomPainter {
  final double width;
  final double height;
  final List<TimelineSegment> segments;

  TimelineTrack({
    required this.width,
    required this.height,
    required this.segments,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    double currentY = 0;

    for (final segment in segments) {
      paint.color = segment.color;
      
      if (segment.isDashed) {
        // Draw dashed line
        final dashWidth = 4.0;
        final dashSpace = 4.0;
        double y = currentY;
        
        while (y < currentY + segment.length) {
          canvas.drawLine(
            Offset(centerX, y),
            Offset(centerX, (y + dashWidth).clamp(0, currentY + segment.length)),
            paint,
          );
          y += dashWidth + dashSpace;
        }
      } else {
        // Draw solid line
        canvas.drawLine(
          Offset(centerX, currentY),
          Offset(centerX, currentY + segment.length),
          paint,
        );
      }

      // Draw node if specified
      if (segment.hasNode) {
        final nodePaint = Paint()
          ..color = segment.nodeColor ?? segment.color
          ..style = PaintingStyle.fill;
        
        canvas.drawCircle(
          Offset(centerX, currentY + segment.length),
          4.0,
          nodePaint,
        );
      }

      currentY += segment.length;
    }
  }

  @override
  bool shouldRepaint(covariant TimelineTrack oldDelegate) {
    return oldDelegate.width != width ||
        oldDelegate.height != height ||
        oldDelegate.segments != segments;
  }
}

class TimelineSegment {
  final double length;
  final Color color;
  final bool isDashed;
  final bool hasNode;
  final Color? nodeColor;

  TimelineSegment({
    required this.length,
    required this.color,
    this.isDashed = false,
    this.hasNode = false,
    this.nodeColor,
  });
}

