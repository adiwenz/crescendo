import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/exercise_attempt.dart';
import '../../models/replay_models.dart';
import '../../models/vocal_exercise.dart';
import '../../services/transposed_exercise_builder.dart';
import '../../services/vocal_range_service.dart';
import '../../models/pitch_highway_difficulty.dart';
import '../widgets/pitch_snapshot_chart.dart';
import 'pitch_highway_review_screen.dart';
import '../../models/last_take.dart';
import '../../models/pitch_frame.dart';

class ExerciseReviewSummaryScreen extends StatefulWidget {
  final VocalExercise exercise;
  final ExerciseAttempt attempt;

  const ExerciseReviewSummaryScreen({
    super.key,
    required this.exercise,
    required this.attempt,
  });

  @override
  State<ExerciseReviewSummaryScreen> createState() => _ExerciseReviewSummaryScreenState();
}

class _ExerciseReviewSummaryScreenState extends State<ExerciseReviewSummaryScreen> {
  final VocalRangeService _vocalRangeService = VocalRangeService();
  List<PitchSample> _samples = const [];
  List<TargetNote> _targets = const [];
  List<ExerciseSegment> _segments = const [];
  int _durationMs = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReviewData();
  }

  Future<void> _loadReviewData() async {
    // Parse contour data (pitch samples)
    _samples = _parseContour(widget.attempt.contourJson);
    
    // Parse target notes from saved data or build from exercise
    _targets = _parseTargetNotes(widget.attempt.targetNotesJson) ?? 
        await _buildTargetNotesFromExercise();
    
    // Parse segments
    _segments = _parseSegments(widget.attempt.segmentsJson);
    
    // Calculate duration
    if (_samples.isNotEmpty) {
      _durationMs = _samples.map((s) => s.timeMs).reduce(math.max);
    } else if (_targets.isNotEmpty) {
      _durationMs = _targets.map((t) => t.endMs).reduce(math.max);
    } else {
      _durationMs = 6000; // Default
    }
    
    setState(() => _loading = false);
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

  List<TargetNote>? _parseTargetNotes(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded.map<TargetNote>((item) {
        final map = item as Map<String, dynamic>;
        return TargetNote(
          startMs: (map['startMs'] as num).toInt(),
          endMs: (map['endMs'] as num).toInt(),
          midi: (map['midi'] as num).toDouble(),
          label: map['label'] as String?,
        );
      }).toList();
    } catch (_) {
      return null;
    }
  }

  List<ExerciseSegment> _parseSegments(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map<ExerciseSegment>((item) {
        final map = item as Map<String, dynamic>;
        return ExerciseSegment(
          segmentIndex: (map['segmentIndex'] as num).toInt(),
          startMs: (map['startMs'] as num).toInt(),
          endMs: (map['endMs'] as num).toInt(),
          transposeSemitone: (map['transposeSemitone'] as num).toInt(),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<TargetNote>> _buildTargetNotesFromExercise() async {
    // Fallback: build from exercise if target notes weren't saved
    final (lowestMidi, highestMidi) = await _vocalRangeService.getRange();
    final difficulty = widget.attempt.pitchDifficulty != null
        ? pitchHighwayDifficultyFromName(widget.attempt.pitchDifficulty!)
        : PitchHighwayDifficulty.medium;
    
    final notes = TransposedExerciseBuilder.buildTransposedSequence(
      exercise: widget.exercise,
      lowestMidi: lowestMidi,
      highestMidi: highestMidi,
      leadInSec: 2.0,
      difficulty: difficulty,
    );
    
    return notes.map((n) {
      return TargetNote(
        startMs: (n.startSec * 1000).round(),
        endMs: (n.endSec * 1000).round(),
        midi: n.midi.toDouble(),
        label: n.lyric,
      );
    }).toList();
  }

  void _openFullReplay() {
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
          startTimeSec: 0.0,
        ),
      ),
    );
  }

  void _openSegmentReplay(ExerciseSegment segment) {
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
          startTimeSec: segment.startMs / 1000.0,
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Review: ${widget.exercise.name}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Overall Score
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Overall Score',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${widget.attempt.overallScore.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Overview Graph
            const Text(
              'Overview',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (_samples.isNotEmpty && _targets.isNotEmpty)
              _OverviewGraph(
                samples: _samples,
                targets: _targets,
                segments: _segments,
                durationMs: _durationMs,
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No pitch data available'),
              ),
            
            const SizedBox(height: 32),
            
            // Actions
            const Text(
              'Review Options',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _samples.isEmpty ? null : _openFullReplay,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Review Full Take'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            
            if (_segments.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Jump to Segment',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ..._segments.map((segment) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed: () => _openSegmentReplay(segment),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Segment ${segment.segmentIndex + 1} '
                          '(+${segment.transposeSemitone} semitones)',
                        ),
                        Text(
                          '${_formatTime(segment.startMs)} - ${_formatTime(segment.endMs)}',
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodySmall?.color,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(int ms) {
    final totalSeconds = (ms / 1000).floor();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class ExerciseSegment {
  final int segmentIndex;
  final int startMs;
  final int endMs;
  final int transposeSemitone;

  const ExerciseSegment({
    required this.segmentIndex,
    required this.startMs,
    required this.endMs,
    required this.transposeSemitone,
  });
}

class _OverviewGraph extends StatelessWidget {
  final List<PitchSample> samples;
  final List<TargetNote> targets;
  final List<ExerciseSegment> segments;
  final int durationMs;

  const _OverviewGraph({
    required this.samples,
    required this.targets,
    required this.segments,
    required this.durationMs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: const Color(0xFFF0F3F6)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: Stack(
              children: [
                // Main graph
                PitchSnapshotView(
                  targetNotes: targets,
                  pitchSamples: samples,
                  durationMs: durationMs,
                  height: 200,
                ),
                // Segment markers - positioned using LayoutBuilder to get actual graph width
                if (segments.isNotEmpty)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final graphWidth = constraints.maxWidth;
                      return Stack(
                        children: segments.map((segment) {
                          final x = (segment.startMs / durationMs) * graphWidth;
                          return Positioned(
                            left: x.clamp(0.0, graphWidth - 2),
                            top: 0,
                            bottom: 0,
                            child: Container(
                              width: 2,
                              color: Colors.blue.withOpacity(0.3),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.2),
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(4),
                                        topRight: Radius.circular(4),
                                      ),
                                    ),
                                    child: Text(
                                      'S${segment.segmentIndex + 1}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.blue,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
