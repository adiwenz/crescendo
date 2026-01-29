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
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.blurSigma = 14,
    this.fillColor,
    this.borderColor,
    this.shadow,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    if (!colors.isDark) {
      // Light mode: frosted glass style
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: fillColor ?? colors.surfaceGlass,
          borderRadius: borderRadius,
          border: Border.all(color: borderColor ?? colors.borderGlass, width: 1),
          boxShadow: shadow ?? colors.elevationShadow,
        ),
        child: child,
      );
    }
    // Dark mode: backdrop blur
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
            boxShadow: shadow ?? colors.elevationShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}
