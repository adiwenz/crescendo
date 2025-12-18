import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/frosted_card.dart';

class LandingHomeScreen extends StatelessWidget {
  const LandingHomeScreen({super.key});

  void _open(BuildContext context, String route) {
    Navigator.pushNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    final entries = [
      _NavRow(label: 'Settings', onTap: () => _open(context, '/settings')),
      _NavRow(
          label: 'Exercise Library', onTap: () => _open(context, '/library')),
      _NavRow(label: 'Piano', onTap: () => _open(context, '/piano')),
      _NavRow(label: 'Progress', onTap: () => _open(context, '/progress')),
    ];
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Spacer(),
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Image.asset(
                    'assets/icon.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Crescendo',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Grow your voice with guided exercises and simple tools.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const Spacer(),
                Column(
                  children: entries
                      .map(
                        (row) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: row,
                        ),
                      )
                      .toList(),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _NavRow({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: FrostedCard(
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Icon(Icons.chevron_right, color: colors.iconMuted),
          ],
        ),
      ),
    );
  }
}
