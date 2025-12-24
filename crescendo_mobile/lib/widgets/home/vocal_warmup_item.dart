import 'package:flutter/material.dart';

class VocalWarmupItem extends StatelessWidget {
  final String title;
  final bool isCompleted;
  final VoidCallback? onTap;

  const VocalWarmupItem({
    super.key,
    required this.title,
    required this.isCompleted,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                // Left side: teal circle with check or outlined circle
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? const Color(0xFF7FD1B9) // Mint/teal
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isCompleted
                          ? const Color(0xFF7FD1B9)
                          : const Color(0xFFD1D1D6),
                      width: isCompleted ? 0 : 2,
                    ),
                  ),
                  child: isCompleted
                      ? const Icon(
                          Icons.check,
                          size: 16,
                          color: Colors.white,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF2E2E2E),
                  ),
                ),
              ],
            ),
            // Right side: subtle check indicator
            if (isCompleted)
              const Icon(
                Icons.check,
                size: 20,
                color: Color(0xFFA5A5A5),
              ),
          ],
        ),
      ),
    );
  }
}

