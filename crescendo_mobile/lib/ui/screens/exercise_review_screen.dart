import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/exercise_attempt.dart';
import '../../models/last_take.dart';
import '../../models/pitch_frame.dart';
import '../../models/replay_models.dart';
import '../../models/vocal_exercise.dart';
import '../../services/attempt_repository.dart';
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
  final AttemptRepository _attempts = AttemptRepository.instance;
  List<PitchSample> _samples = const [];
  List<TargetNote> _targets = const [];
  int _durationMs = 6000;
  late ExerciseAttempt _currentAttempt;

  @override
  void initState() {
    super.initState();
    _currentAttempt = widget.attempt;
    _loadReplayData(_currentAttempt);
    _attempts.addListener(_onAttemptsChanged);
    _attempts.ensureLoaded().then((_) => _refreshFromRepo());
  }

  @override
  void dispose() {
    _attempts.removeListener(_onAttemptsChanged);
    super.dispose();
  }

  void _onAttemptsChanged() {
    _refreshFromRepo();
  }

  void _refreshFromRepo() {
    final latest = _attempts.latestFor(widget.exercise.id);
    if (latest == null || latest.id == _currentAttempt.id) return;
    if (!mounted) return;
    setState(() {
      _currentAttempt = latest;
      _loadReplayData(_currentAttempt);
    });
  }

  void _loadReplayData(ExerciseAttempt attempt) {
    _samples = _parseContour(attempt.contourJson);
    _durationMs = _samples.isEmpty
        ? 6000
        : _samples.map((s) => s.timeMs).reduce((a, b) => a > b ? a : b);
    _targets = _buildTargetNotes(widget.exercise);
  }

  @override
  Widget build(BuildContext context) {
    final attempt = _currentAttempt;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      'Review: ${widget.exercise.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Last score: ${attempt.overallScore.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _samples.isEmpty ? null : _openReplay,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play recording'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_samples.isNotEmpty)
                PitchSnapshotView(
                  targetNotes: _targets,
                  pitchSamples: _samples,
                  durationMs: _durationMs,
                  height: 220,
                ),
              if (_samples.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No contour available for this take'),
                ),
            ],
          ),
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
      recordedAt: _currentAttempt.completedAt ?? DateTime.now(),
      frames: frames,
      durationSec: _durationMs / 1000.0,
      audioPath: _currentAttempt.recordingPath,
      pitchDifficulty: _currentAttempt.pitchDifficulty,
    );
  }
}
