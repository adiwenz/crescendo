import 'package:flutter/material.dart';

class QuickActionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color cardTintColor;
  final VoidCallback? onTap;

  const QuickActionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.cardTintColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: cardTintColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFFE6E1DC),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: const Color(0xFF2E2E2E),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2E2E2E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
