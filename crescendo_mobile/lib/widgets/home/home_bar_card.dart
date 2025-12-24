import 'package:flutter/material.dart';

class HomeBarCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final Alignment? alignment;

  const HomeBarCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.width,
    this.alignment,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      width: width,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0xFFE6E1DC).withOpacity(0.6),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );

    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: content,
      );
    }

    if (alignment != null) {
      return Align(
        alignment: alignment!,
        child: content,
      );
    }

    return content;
  }
}

