import 'package:flutter/material.dart';

class StartTrainingCTA extends StatelessWidget {
  final VoidCallback? onTap;

  const StartTrainingCTA({
    super.key,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFF1D27A).withOpacity(0.3), // Warm butter/yellow tint
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: const Color(0xFFE6E1DC),
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            'Start Training Session',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2E2E2E),
            ),
          ),
        ),
      ),
    );
  }
}

