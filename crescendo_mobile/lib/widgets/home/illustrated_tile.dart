import 'package:flutter/material.dart';

class IllustratedTile extends StatelessWidget {
  final String label;
  final String? subtitle;
  final String illustrationPath;
  final Color backgroundColor;
  final VoidCallback? onTap;

  const IllustratedTile({
    super.key,
    required this.label,
    required this.illustrationPath,
    required this.backgroundColor,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AspectRatio(
        aspectRatio: 1.0, // Make it square (1:1 ratio)
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFFE6E1DC),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Centered illustration icon
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Image.asset(
                    illustrationPath,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox(),
                  ),
                ),
                const SizedBox(height: 8),
                // Label
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2E2E2E),
                    height: 1.0,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  // Subtitle
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF7A7A7A),
                      height: 1.0,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
