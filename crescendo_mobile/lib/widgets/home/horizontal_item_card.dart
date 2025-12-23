import 'package:flutter/material.dart';
import 'accent_chip.dart';

class HorizontalItemCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color accentColor;
  final VoidCallback? onTap;

  const HorizontalItemCard({
    super.key,
    required this.title,
    required this.icon,
    required this.accentColor,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.90),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFE6E1DC).withOpacity(0.6),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 24,
              spreadRadius: 0,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AccentChip(icon: icon, accentColor: accentColor, size: 40),
            const SizedBox(height: 10),
            Flexible(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2E2E2E),
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF7A7A7A),
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

