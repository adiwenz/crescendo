import 'package:flutter/material.dart';
import '../../models/pitch_frame.dart';
import '../../controllers/sustained_hold_controller.dart';
import '../../utils/pitch_math.dart';
import '../theme/app_theme.dart';

class PitchContourCard extends StatelessWidget {
  final double targetMidi;
  final List<PitchFrame> frames;
  final double height;
  final double width;

  const PitchContourCard({
    super.key,
    required this.targetMidi,
    required this.frames,
    this.height = 100,
    this.width = double.infinity,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: colors.surface0, // Using standard surface color, adjust if needed
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CustomPaint(
          painter: _PitchContourPainter(
            targetMidi: targetMidi,
            frames: frames,
            lineColor: colors.textPrimary,
            snappedColor: colors.lavenderGlow,
            targetNoteColor: Colors.grey.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

class _PitchContourPainter extends CustomPainter {
  final double targetMidi;
  final List<PitchFrame> frames;
  final Color lineColor;
  final Color snappedColor;
  final Color targetNoteColor;

  _PitchContourPainter({
    required this.targetMidi,
    required this.frames,
    required this.lineColor,
    required this.snappedColor,
    required this.targetNoteColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (frames.isEmpty) return;

    // Draw Target Line
    final paintTarget = Paint()
      ..color = targetNoteColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
      
    // Center vertically is the target pitch
    final centerY = size.height / 2;
    
    // Draw dashed target line
    const double dashWidth = 5;
    double dashSpace = 5;
    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(Offset(startX, centerY), Offset(startX + dashWidth, centerY), paintTarget);
      startX += dashWidth + dashSpace;
    }
    
    // Setup Pitch Curve
    // X-axis: Time (normalized to frame count for simplicity, or relative time)
    // Y-axis: Pitch Error (clamped visuals)
    
    // Range to show: ±2 semitones seems reasonable for error visibility
    const rangeMidi = 2.0; 
    
     // Prepare path segments
    // We draw segment by segment to handle color changes (snapped/unsnapped)
    
    // We need smoothed data? Or raw? 
    // The frames stores raw data. 
    // Let's do simple smoothing here or just plot raw. 
    // Raw might be jittery. Ideally controller saves "processed" frames.
    // For now, let's just plot what we have.
    
    final paintLine = Paint()
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
      
   final paintGlow = Paint()
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = snappedColor.withValues(alpha: 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    if (frames.length < 2) return;
    
    final startTime = frames.first.time;
    final endTime = frames.last.time;
    final duration = endTime - startTime;
    
    if (duration <= 0) return;

    for (int i = 0; i < frames.length - 1; i++) {
        final f1 = frames[i];
        final f2 = frames[i+1];
        
        final hz1 = f1.hz;
        if (hz1 == null || hz1 <= 0) continue;
        final hz2 = f2.hz;
        if (hz2 == null || hz2 <= 0) continue; // Skip silence gaps
        
        // Calculate coords
        final t1 = (f1.time - startTime) / duration;
        final t2 = (f2.time - startTime) / duration;
        
        final x1 = t1 * size.width;
        final x2 = t2 * size.width;
        
        final m1 = PitchMath.hzToMidi(hz1);
        final m2 = PitchMath.hzToMidi(hz2); // Note: Simple linear interpolation
        
        final dy1 = (targetMidi - m1) / rangeMidi * (size.height / 2);
        final dy2 = (targetMidi - m2) / rangeMidi * (size.height / 2);
        
        final y1 = (size.height / 2) + dy1;
        final y2 = (size.height / 2) + dy2;
        
        // Check "snapped" status
        // We replicate snapping logic here purely for visualization (or store it in frames)
        // Controller used 30 cents = 0.3 semitones.
        final error1 = (m1 - targetMidi).abs() * 100;
        final isSnapped = error1 <= SustainedHoldController.snapThresholdCents; 
        
        if (isSnapped) {
            // Draw glow underlay
            canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paintGlow);
            paintLine.color = snappedColor;
        } else {
            paintLine.color = lineColor;
        }
        
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paintLine);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // Simple invalidation
  }
}
