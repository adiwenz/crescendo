import 'package:flutter/material.dart';

import '../../services/range_store.dart';
import '../../utils/pitch_math.dart';
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

  @override
  void initState() {
    super.initState();
    _loadRange();
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
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Settings'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          if (i == 0) return _rangeCard(context);
          return items[i - 1];
        },
      ),
    );
  }

  Widget _rangeCard(BuildContext context) {
    final lowestLabel = _lowest != null ? PitchMath.midiToName(_lowest!) : '—';
    final highestLabel = _highest != null ? PitchMath.midiToName(_highest!) : '—';
    final rangeLabel = (_lowest != null && _highest != null)
        ? '$lowestLabel to $highestLabel'
        : 'Run Find your range to capture.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Saved Range',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
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
                      color: Colors.grey[600],
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
