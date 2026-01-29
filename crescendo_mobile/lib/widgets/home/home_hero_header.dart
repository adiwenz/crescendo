import 'package:flutter/material.dart';

import '../../design/app_text.dart';
import '../../screens/home/styles.dart';

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
      ..shader = HomeScreenStyles.heroBaseGradient.createShader(
          Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, base);

    final paint1 = Paint()
      ..shader = HomeScreenStyles.heroWave1Gradient.createShader(
          Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final paint2 = Paint()
      ..shader = HomeScreenStyles.heroWave2Gradient.createShader(
          Rect.fromLTWH(0, 0, size.width, size.height))
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

    final notePaint = Paint()..color = HomeScreenStyles.heroBokehColor;
    canvas.drawCircle(Offset(size.width * 0.8, size.height * 0.25), 10, notePaint);
    canvas.drawCircle(Offset(size.width * 0.7, size.height * 0.3), 6, notePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
