import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/exercise_attempt.dart';
import '../../models/replay_models.dart';
import '../../models/vocal_exercise.dart';
import '../../services/audio_synth_service.dart';
import '../widgets/pitch_highway_replay.dart';
import '../widgets/pitch_snapshot_chart.dart';

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
  List<PitchSample> _samples = const [];
  List<TargetNote> _targets = const [];
  int _durationMs = 6000;
  ViewMode _mode = ViewMode.replay;
  final GlobalKey<PitchHighwayReplayState> _replayKey = GlobalKey();

  @override
  void dispose() {
    _synth.stop();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadReplayData();
  }

  void _loadReplayData() {
    _samples = _parseContour(widget.attempt.contourJson);
    _durationMs = _samples.isEmpty
        ? 6000
        : _samples.map((s) => s.timeMs).reduce((a, b) => a > b ? a : b);
    _targets = _buildTargetNotes(widget.exercise);
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
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    if (_mode != ViewMode.replay) {
                      setState(() => _mode = ViewMode.replay);
                    }
                    _replayKey.currentState?.replay();
                    _playRecording();
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Replay recording'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _mode = _mode == ViewMode.replay
                          ? ViewMode.snapshot
                          : ViewMode.replay;
                    });
                  },
                  child: Text(_mode == ViewMode.replay
                      ? 'Snapshot view'
                      : 'Replay view'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_samples.isNotEmpty && _mode == ViewMode.replay)
              PitchHighwayReplay(
                key: _replayKey,
                targetNotes: _targets,
                recordedSamples: _samples,
                takeDurationMs: _durationMs,
                height: 360,
                showControls: true,
              ),
            if (_samples.isNotEmpty && _mode == ViewMode.snapshot)
              PitchSnapshotChart(
                targetNotes: _targets,
                recordedSamples: _samples,
                durationMs: _durationMs,
                height: 260,
              ),
            if (_samples.isEmpty) const Text('No contour available for this take'),
          ],
        ),
      ),
    );
  }

  List<PitchSample> _parseContour(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map<PitchSample>((item) {
        final map = item as Map<String, dynamic>;
        final time = (map['t'] ?? map['time'] ?? 0) as num;
        final hz = map['hz'] as num?;
        final midi = map['midi'] as num?;
        return PitchSample(
          timeMs: (time * 1000).round(),
          midi: midi?.toDouble(),
          freqHz: hz?.toDouble(),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  List<TargetNote> _buildTargetNotes(VocalExercise exercise) {
    final spec = exercise.highwaySpec;
    if (spec == null || spec.segments.isEmpty) return const [];
    return spec.segments.map((s) {
      return TargetNote(
        startMs: s.startMs,
        endMs: s.endMs,
        midi: s.midiNote.toDouble(),
        label: s.label,
      );
    }).toList();
  }
}

enum ViewMode { replay, snapshot }
