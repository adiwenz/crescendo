import 'package:flutter/material.dart';

class ProgressStarRow extends StatelessWidget {
  final int stars;
  const ProgressStarRow({super.key, required this.stars});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final filled = i < stars;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            filled ? Icons.star_rounded : Icons.star_border_rounded,
            color: filled ? Colors.amber : Colors.grey.shade400,
            size: 28,
          ),
        );
      }),
    );
  }
}
