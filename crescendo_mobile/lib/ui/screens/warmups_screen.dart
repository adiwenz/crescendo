import 'package:flutter/material.dart';

import '../../models/warmup.dart';
import '../../services/audio_synth_service.dart';
import '../state.dart';
import '../widgets/piano_widget.dart';

class WarmupsScreen extends StatefulWidget {
  const WarmupsScreen({super.key});

  @override
  State<WarmupsScreen> createState() => _WarmupsScreenState();
}

class _WarmupsScreenState extends State<WarmupsScreen> {
  final synth = AudioSynthService();
  final appState = AppState();
  List<String> customNotes = [];
  String? _lastPreview;

  @override
  Widget build(BuildContext context) {
    final warmups = [...WarmupsLibrary.defaults, _buildCustomWarmup()];
    return Scaffold(
      appBar: AppBar(title: const Text('Warmups')),
      body: ListView.builder(
        itemCount: warmups.length + 1,
        itemBuilder: (context, idx) {
          if (idx == 0) {
            return _buildPianoCard();
          }
          final warmup = warmups[idx - 1];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              title: Text(warmup.name),
              subtitle: Text(warmup.id),
              trailing: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () async {
                      final path = await synth.renderWarmup(warmup);
                      setState(() => _lastPreview = path);
                      await synth.playFile(path);
                    },
                    child: const Text('Preview'),
                  ),
                  ElevatedButton(
                    onPressed: () => appState.selectedWarmup.value = warmup,
                    child: const Text('Use'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  WarmupDefinition _buildCustomWarmup() {
    final notes = customNotes.isEmpty ? ['C4'] : customNotes;
    final durations = List<double>.filled(notes.length, 0.5);
    return WarmupDefinition(
      id: 'user_piano',
      name: 'User piano reference',
      notes: notes,
      durations: durations,
      gap: 0.1,
    );
  }

  Widget _buildPianoCard() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('User piano reference', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            PianoWidget(
              keys: const ['C4', 'D4', 'E4', 'F4', 'G4', 'A4', 'B4', 'C5', 'D5', 'E5'],
              onTap: (n) => setState(() => customNotes = [...customNotes, n]),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    final warmup = _buildCustomWarmup();
                    appState.customNotes = warmup.notes;
                    appState.selectedWarmup.value = warmup;
                    final path = await synth.renderWarmup(warmup);
                    await synth.playFile(path);
                  },
                  child: const Text('Preview reference'),
                ),
                TextButton(
                  onPressed: () => setState(() => customNotes = []),
                  child: const Text('Clear'),
                ),
              ],
            ),
            if (_lastPreview != null) Text('Last preview file: $_lastPreview', style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
