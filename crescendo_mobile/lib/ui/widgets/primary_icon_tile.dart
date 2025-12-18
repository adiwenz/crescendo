import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'frosted_card.dart';

class PrimaryIconTile extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback onTap;

  const PrimaryIconTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: FrostedCard(
            borderRadius: BorderRadius.circular(22),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconTheme(
                    data: const IconThemeData(color: AppColors.textPrimary, size: 36),
                    child: icon,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall,
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
