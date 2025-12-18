import 'package:flutter/material.dart';

class NoteDisplayCard extends StatelessWidget {
  final String note;
  final String freqLabel;
  final bool inTune;
  final Widget? meter;

  const NoteDisplayCard({
    super.key,
    required this.note,
    required this.freqLabel,
    required this.inTune,
    this.meter,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Now Playing', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  note,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                Text(freqLabel, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Icon(
                  inTune ? Icons.check_circle : Icons.circle_outlined,
                  color: inTune ? Colors.green : Colors.black26,
                ),
              ],
            ),
            if (meter != null) ...[
              const SizedBox(height: 12),
              meter!,
            ],
          ],
        ),
      ),
    );
  }
}
