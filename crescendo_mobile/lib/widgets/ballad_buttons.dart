
import 'package:flutter/material.dart';
import '../../theme/ballad_theme.dart';

class BalladPrimaryButton extends StatelessWidget {
  const BalladPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56, // Enforce height for consistency
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: BalladTheme.primaryButtonGradient,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 24), // Vertical 0 because height is fixed
          ),
          onPressed: isLoading ? null : onPressed,
          child: isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        style: BalladTheme.labelLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class BalladSecondaryButton extends StatelessWidget {
  const BalladSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(
        label,
        style: BalladTheme.bodyMedium.copyWith(decoration: TextDecoration.underline),
      ),
    );
  }
}
