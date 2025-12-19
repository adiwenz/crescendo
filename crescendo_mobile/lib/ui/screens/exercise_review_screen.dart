import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/exercise_attempt.dart';
import '../../models/last_take.dart';
import '../../models/pitch_frame.dart';
import '../../models/replay_models.dart';
import '../../models/vocal_exercise.dart';
import '../widgets/pitch_snapshot_chart.dart';
import 'pitch_highway_review_screen.dart';

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
  List<PitchSample> _samples = const [];
  List<TargetNote> _targets = const [];
  int _durationMs = 6000;

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
              onPressed: _samples.isEmpty ? null : _openReplay,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Replay on highway'),
            ),
            const SizedBox(height: 24),
            const Text('Snapshot', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_samples.isNotEmpty)
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

  void _openReplay() {
    final take = _buildLastTake();
    if (take == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No recorded take available')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PitchHighwayReviewScreen(
          exercise: widget.exercise,
          lastTake: take,
        ),
      ),
    );
  }

  LastTake? _buildLastTake() {
    if (_samples.isEmpty) return null;
    final frames = _samples.map((s) {
      return PitchFrame(
        time: s.timeMs / 1000.0,
        hz: s.freqHz,
        midi: s.midi,
      );
    }).toList();
    return LastTake(
      exerciseId: widget.exercise.id,
      recordedAt: widget.attempt.completedAt ?? DateTime.now(),
      frames: frames,
      durationSec: _durationMs / 1000.0,
      audioPath: widget.attempt.recordingPath,
      pitchDifficulty: widget.attempt.pitchDifficulty,
    );
  }
}
