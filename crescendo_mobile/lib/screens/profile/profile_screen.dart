import 'package:flutter/material.dart';

import '../../services/vocal_range_service.dart';
import '../../ui/screens/select_vocal_range_screen.dart';
import '../../state/library_store.dart';
import '../../widgets/ballad_scaffold.dart';
import '../../widgets/frosted_panel.dart';
import '../../widgets/ballad_buttons.dart';
import '../../theme/ballad_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final VocalRangeService _vocalRangeService = VocalRangeService();
  String? _rangeDisplay;
  bool _hasCustomRange = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRange();
  }

  Future<void> _loadRange() async {
    setState(() {
      _loading = true;
    });
    final range = await _vocalRangeService.getRangeDisplay();
    final hasCustom = await _vocalRangeService.hasCustomRange();
    setState(() {
      _rangeDisplay = range;
      _hasCustomRange = hasCustom;
      _loading = false;
    });
  }

  Future<void> _setRange() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SelectVocalRangeScreen()),
    );
    if (result == true && mounted) {
      await _loadRange();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vocal range saved')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BalladScaffold(
      title: 'Profile',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: Colors.white.withOpacity(0.2),
              child: const Icon(Icons.person, size: 40, color: Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'User',
              style: BalladTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 32),
          
          // Vocal Range Section
          FrostedPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vocal Range', 
                  style: BalladTheme.bodyLarge.copyWith(fontWeight: FontWeight.bold)
                ),
                const SizedBox(height: 8),
                _loading
                    ? const SizedBox(
                        height: 20,
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      )
                    : Text(
                        _hasCustomRange
                            ? 'Range: $_rangeDisplay'
                            : 'Setting your vocal range will personalize exercises to fit your voice.',
                        style: BalladTheme.bodyMedium,
                      ),
                const SizedBox(height: 16),
                BalladPrimaryButton(
                  label: 'Set Range',
                  onPressed: _setRange,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Settings
          FrostedPanel(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                _settingsRow(context, 'Subscription', () => Navigator.pushNamed(context, '/settings/subscription')),
                Divider(color: Colors.white.withOpacity(0.1), height: 1),
                _settingsRow(context, 'Preferences', () => Navigator.pushNamed(context, '/settings')),
              ],
            ),
          ),

          const SizedBox(height: 24),
          
          // Danger Zone
          SizedBox(
            width: double.infinity,
            child: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF1A1A2E),
                    title: const Text('Reset progress?', style: TextStyle(color: Colors.white)),
                    content: const Text('This will clear completed exercises.', style: TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await libraryStore.reset();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Progress reset')));
                  }
                }
              },
              child: const Text('Reset progress'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsRow(BuildContext context, String title, VoidCallback onTap) {
    return ListTile(
      title: Text(title, style: BalladTheme.bodyMedium),
      trailing: Icon(Icons.chevron_right, color: BalladTheme.textSecondary),
      onTap: onTap,
    );
  }
}
