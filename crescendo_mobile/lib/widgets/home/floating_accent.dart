import 'package:flutter/material.dart';

class FloatingAccent extends StatelessWidget {
  final Widget child;
  final Offset offset;
  final double? width;
  final double? height;

  const FloatingAccent({
    super.key,
    required this.child,
    required this.offset,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: offset.dx,
      top: offset.dy,
      width: width,
      height: height,
      child: child,
    );
  }
}

class PinkGradientSquare extends StatelessWidget {
  const PinkGradientSquare({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF4A3C4), // Blush pink
            Color(0xFFF3B7A6), // Soft peach
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    );
  }
}

class PurpleChatBubble extends StatelessWidget {
  const PurpleChatBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFFB9B6F3), // Pastel lavender
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(
        Icons.chat_bubble_outline,
        size: 18,
        color: Colors.white,
      ),
    );
  }
}

class OrangeCapsuleButton extends StatelessWidget {
  final VoidCallback? onTap;

  const OrangeCapsuleButton({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 24,
        height: 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF3B7A6), // Soft peach
              Color(0xFFF1D27A), // Butter yellow
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 12,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.arrow_forward,
          size: 16,
          color: Colors.white,
        ),
      ),
    );
  }
}

