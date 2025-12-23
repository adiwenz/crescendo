import 'package:flutter/material.dart';

class WatermarkImage extends StatelessWidget {
  final String imagePath;
  final double opacity;
  final Alignment alignment;
  final double? width;
  final double? height;

  const WatermarkImage({
    super.key,
    required this.imagePath,
    this.opacity = 0.12,
    this.alignment = Alignment.centerRight,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: Opacity(
          opacity: opacity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: width ?? 100,
              height: height ?? 100,
              child: Image.asset(
                imagePath,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

