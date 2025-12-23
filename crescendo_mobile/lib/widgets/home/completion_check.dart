import 'package:flutter/material.dart';

class CompletionCheck extends StatelessWidget {
  final bool isCompleted;
  final VoidCallback? onTap;

  const CompletionCheck({
    super.key,
    required this.isCompleted,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: isCompleted ? const Color(0xFF8FC9A8) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isCompleted
                ? const Color(0xFF8FC9A8)
                : const Color(0xFFE6E1DC),
            width: 2,
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
    );
  }
}

