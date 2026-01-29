import 'package:flutter/material.dart';

import '../../services/vocal_range_service.dart';
import '../../ui/screens/select_vocal_range_screen.dart';
import '../../state/library_store.dart';

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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const CircleAvatar(
              radius: 36,
              child: Icon(Icons.person, size: 36),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'User',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 24),
            // Vocal Range Section
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Vocal Range'),
                  subtitle: _loading
                      ? const SizedBox(
                          height: 20,
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : _hasCustomRange
                          ? Text(
                              'Range: $_rangeDisplay',
                              style: Theme.of(context).textTheme.bodyMedium,
                            )
                          : Text(
                              'Setting your vocal range will personalize exercises to fit your voice.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _setRange,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Set Range'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _settingsRow(context, 'Subscription', () {}),
            _settingsRow(context, 'Preferences', () {}),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Reset progress?'),
                    content: const Text('This will clear completed exercises.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
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
          ],
        ),
      ),
    );
  }

  Widget _settingsRow(BuildContext context, String title, VoidCallback onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
