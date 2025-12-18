import 'package:flutter/material.dart';

import '../../services/range_store.dart';
import '../../utils/pitch_math.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/frosted_card.dart';
import 'find_range_lowest_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final RangeStore _rangeStore = RangeStore();
  int? _lowest;
  int? _highest;
  bool _loaded = false;
  bool _useSystemTheme = true;
  bool _lightMode = false;

  @override
  void initState() {
    super.initState();
    _loadRange();
    final mode = AppThemeController.mode.value;
    _useSystemTheme = mode == ThemeMode.system;
    _lightMode = mode == ThemeMode.light;
  }

  Future<void> _loadRange() async {
    final range = await _rangeStore.getRange();
    if (!mounted) return;
    setState(() {
      _lowest = range.$1;
      _highest = range.$2;
      _loaded = true;
    });
  }

  void _openFindRange() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FindRangeLowestScreen()),
    );
    if (result == true) {
      await _loadRange();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      _SettingsItem(
        title: 'Find your range',
        subtitle: 'Quick check of your vocal range',
        onTap: _openFindRange,
      ),
      _SettingsItem(
        title: 'Subscription',
        subtitle: 'View plan and billing',
        onTap: () => Navigator.pushNamed(context, '/settings/subscription'),
      ),
      _SettingsItem(
        title: 'Subscription features',
        subtitle: 'What you get with premium',
        onTap: () => Navigator.pushNamed(context, '/settings/subscription_features'),
      ),
    ];
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Settings'),
      ),
      body: AppBackground(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length + 2,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            if (i == 0) return _themeCard(context);
            if (i == 1) return _rangeCard(context);
            return items[i - 2];
          },
        ),
      ),
    );
  }

  Widget _themeCard(BuildContext context) {
    final colors = AppThemeColors.of(context);
    return FrostedCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Appearance',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _useSystemTheme,
            title: const Text('Use system theme'),
            onChanged: (value) {
              setState(() => _useSystemTheme = value);
              AppThemeController.mode.value =
                  value ? ThemeMode.system : (_lightMode ? ThemeMode.light : ThemeMode.dark);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _lightMode,
            title: const Text('Light mode'),
            onChanged: _useSystemTheme
                ? null
                : (value) {
                    setState(() => _lightMode = value);
                    AppThemeController.mode.value =
                        value ? ThemeMode.light : ThemeMode.dark;
                  },
          ),
        ],
      ),
    );
  }

  Widget _rangeCard(BuildContext context) {
    final colors = AppThemeColors.of(context);
    final lowestLabel = _lowest != null ? PitchMath.midiToName(_lowest!) : '—';
    final highestLabel = _highest != null ? PitchMath.midiToName(_highest!) : '—';
    final rangeLabel = (_lowest != null && _highest != null)
        ? '$lowestLabel to $highestLabel'
        : 'Run Find your range to capture.';
    return FrostedCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Saved Range',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Lowest note: $lowestLabel',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Text(
            'Highest note: $highestLabel',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            rangeLabel,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsItem({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: FrostedCard(
          borderRadius: BorderRadius.circular(16),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
