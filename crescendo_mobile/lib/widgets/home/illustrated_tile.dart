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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.89),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 24,
                    spreadRadius: 0,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Watermark illustration (bottom-right, very low opacity)
                  Positioned(
                    right: -10,
                    bottom: -10,
                    child: Opacity(
                      opacity: 0.08,
                      child: SizedBox(
                        width: 80,
                        height: 80,
                        child: Image.asset(
                          illustrationPath,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox(),
                        ),
                      ),
                    ),
                  ),
                  // Optional readability scrim (left-to-right gradient)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.white.withOpacity(0.92),
                            Colors.white.withOpacity(0.55),
                            Colors.white.withOpacity(0.10),
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // Content (text only, centered)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
