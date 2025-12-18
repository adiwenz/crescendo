import 'package:flutter/material.dart';

import '../../design/app_colors.dart';
import '../../design/app_text.dart';

class HomeHeroHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const HomeHeroHeader({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 140,
      child: Stack(
        children: [
          const Positioned.fill(child: _HeroWaveBackground()),
          SafeArea(
            bottom: false,
            child: Padding(
              padding:
                  const EdgeInsets.only(top: 12, left: 24, right: 24, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(title, style: AppText.h1.copyWith(fontSize: 28)),
                  const SizedBox(height: 6),
                  Text(subtitle, style: AppText.body.copyWith(fontSize: 15)),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

class _HeroWaveBackground extends StatelessWidget {
  const _HeroWaveBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WavePainter(),
    );
  }
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFF7FBFF), Color(0xFFFFFFFF)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, base);

    final paint1 = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFECF4FF), Color(0xFFDDEBFF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final paint2 = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFFF5EA), Color(0xFFFFF1D6)],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final path1 = Path()
      ..moveTo(0, size.height * 0.4)
      ..quadraticBezierTo(size.width * 0.3, size.height * 0.3, size.width * 0.55,
          size.height * 0.55)
      ..quadraticBezierTo(
          size.width * 0.75, size.height * 0.7, size.width, size.height * 0.55)
      ..lineTo(size.width, 0)
      ..lineTo(0, 0);

    final path2 = Path()
      ..moveTo(0, size.height * 0.65)
      ..quadraticBezierTo(size.width * 0.25, size.height * 0.8,
          size.width * 0.55, size.height * 0.7)
      ..quadraticBezierTo(
          size.width * 0.8, size.height * 0.55, size.width, size.height * 0.7)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height);

    canvas.drawPath(path1, paint1);
    canvas.drawPath(path2, paint2);

    final notePaint = Paint()..color = AppColors.accent.withOpacity(0.12);
    canvas.drawCircle(Offset(size.width * 0.8, size.height * 0.25), 10, notePaint);
    canvas.drawCircle(Offset(size.width * 0.7, size.height * 0.3), 6, notePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
