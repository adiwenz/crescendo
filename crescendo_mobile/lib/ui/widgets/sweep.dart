import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../services/sine_sweep_service.dart';

class SineSweepButton extends StatefulWidget {
  const SineSweepButton({super.key});

  @override
  State<SineSweepButton> createState() => _SineSweepButtonState();
}

class _SineSweepButtonState extends State<SineSweepButton> {
  final AudioPlayer _player = AudioPlayer();
  final SineSweepService _sweepService = SineSweepService(sampleRate: 48000);
  bool _busy = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _playSweep() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      const dur = 3.0;

      // G3 -> C5
      const midiStart = 55.0;
      const midiEnd = 72.0;

      final path = await _sweepService.generateSweepWav(
        midiStart: midiStart,
        midiEnd: midiEnd,
        durationSeconds: dur,
        amplitude: 0.2,
        fadeSeconds: 0.01,
      );

      // Stop any current playback cleanly
      await _player.stop();

      // Play the file
      await _player.play(DeviceFileSource(path));
    } catch (e) {
      debugPrint('Sine sweep playback failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sine sweep playback failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _busy ? null : _playSweep,
      icon: const Icon(Icons.play_arrow),
      label: Text(_busy ? 'Preparing…' : 'Play Sine Sweep (G3 → C5)'),
    );
  }
}
