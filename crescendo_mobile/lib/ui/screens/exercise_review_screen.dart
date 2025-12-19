import 'package:flutter/material.dart';

import '../../models/exercise_attempt.dart';
import '../../models/vocal_exercise.dart';
import '../../services/audio_synth_service.dart';

class ExerciseReviewScreen extends StatefulWidget {
  final VocalExercise exercise;
  final ExerciseAttempt attempt;

  const ExerciseReviewScreen({
    super.key,
    required this.exercise,
    required this.attempt,
  });

  @override
  State<ExerciseReviewScreen> createState() => _ExerciseReviewScreenState();
}

class _ExerciseReviewScreenState extends State<ExerciseReviewScreen> {
  final AudioSynthService _synth = AudioSynthService();
  bool _playing = false;

  @override
  void dispose() {
    _synth.stop();
    super.dispose();
  }

  Future<void> _playRecording() async {
    final path = widget.attempt.recordingPath;
    if (path == null || path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No recording available for this take')),
      );
      return;
    }
    setState(() => _playing = true);
    try {
      await _synth.playFile(path);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not play recording: $e')),
      );
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final attempt = widget.attempt;
    return Scaffold(
      appBar: AppBar(
        title: Text('Review: ${widget.exercise.name}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last score: ${attempt.overallScore.toStringAsFixed(0)}'),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _playing ? null : _playRecording,
              icon: const Icon(Icons.play_arrow),
              label: Text(_playing ? 'Playing...' : 'Play recording'),
            ),
            const SizedBox(height: 24),
            if (attempt.contourJson != null && attempt.contourJson!.isNotEmpty)
              Text('Contour data available (render TODO)'),
            if (attempt.contourJson == null || attempt.contourJson!.isEmpty)
              const Text('No contour available for this take'),
          ],
        ),
      ),
    );
  }
}
