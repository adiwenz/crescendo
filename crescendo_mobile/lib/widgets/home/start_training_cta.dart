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
          color: const Color(0xFFF5F5F0), // Neutral light gray/cream
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 24,
              spreadRadius: 0,
              offset: const Offset(0, 10),
            ),
          ],
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
