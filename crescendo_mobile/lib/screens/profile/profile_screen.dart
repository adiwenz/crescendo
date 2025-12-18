import 'package:flutter/material.dart';

import '../../state/library_store.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

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
            _settingsRow(context, 'Range', () {}),
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
