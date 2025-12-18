import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class FrostedCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final double blurSigma;
  final Color? fillColor;
  final Color? borderColor;
  final List<BoxShadow>? shadow;

  const FrostedCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.blurSigma = 14,
    this.fillColor,
    this.borderColor,
    this.shadow,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    if (!colors.isDark) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: fillColor ?? colors.surface1,
          borderRadius: borderRadius,
          border: Border.all(color: borderColor ?? colors.borderSubtle, width: 1),
          boxShadow: shadow ??
              [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
        ),
        child: child,
      );
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: fillColor ?? colors.glassFill,
            borderRadius: borderRadius,
            border: Border.all(color: borderColor ?? colors.glassBorder, width: 1),
            boxShadow: shadow ??
                [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
          ),
          child: child,
        ),
      ),
    );
  }
}
