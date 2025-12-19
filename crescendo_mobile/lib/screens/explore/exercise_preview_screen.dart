import 'package:flutter/material.dart';

import '../../models/vocal_exercise.dart';
import '../../models/exercise_attempt.dart';
import '../../routing/exercise_route_registry.dart';
import '../../services/attempt_repository.dart';
import '../../services/exercise_repository.dart';
import '../../services/audio_synth_service.dart';
import '../../widgets/banner_card.dart';
import '../../ui/screens/exercise_review_screen.dart';
import '../../models/reference_note.dart';
import 'dart:math' as math;

class ExercisePreviewScreen extends StatefulWidget {
  final String exerciseId;

  const ExercisePreviewScreen({super.key, required this.exerciseId});

  @override
  State<ExercisePreviewScreen> createState() => _ExercisePreviewScreenState();
}

class _ExercisePreviewScreenState extends State<ExercisePreviewScreen> {
  final ExerciseRepository _repo = ExerciseRepository();
  final AttemptRepository _attempts = AttemptRepository.instance;
  final AudioSynthService _synth = AudioSynthService();
  VocalExercise? _exercise;
  ExerciseAttemptInfo? _latest;
  bool _loading = true;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[Preview] exerciseId=${widget.exerciseId}');
    _load();
  }

  @override
  void dispose() {
    _synth.stop();
    super.dispose();
  }

  Future<void> _load() async {
    final ex = _repo.getExercises().firstWhere(
      (e) => e.id == widget.exerciseId,
      orElse: () => _repo.getExercises().first,
    );
    await _attempts.ensureLoaded();
    final latest = _attempts.latestFor(widget.exerciseId);
    if (latest == null) {
      debugPrint('[Preview] latest attempt not found for ${widget.exerciseId}');
    }
    if (!mounted) return;
    setState(() {
      _exercise = ex;
      _latest = latest == null ? null : ExerciseAttemptInfo.fromAttempt(latest);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ex = _exercise;
    return Scaffold(
      appBar: AppBar(title: Text(ex?.name ?? 'Exercise')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (ex != null) _Header(ex: ex),
                const SizedBox(height: 16),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Purpose', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(ex?.purpose ?? ex?.description ?? 'Build control and accuracy.'),
                        const SizedBox(height: 16),
                        const Text('How it works', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(ex?.description ?? 'Follow along and match the guide.'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Preview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(ex?.description ?? 'A quick preview of the exercise.'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _previewing || ex == null ? null : () => _playPreview(ex),
                              icon: Icon(_previewing ? Icons.pause : Icons.play_arrow),
                              label: Text(_previewing ? 'Playing…' : 'Play preview'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _startExercise,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text('Start Exercise'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _latest == null ? null : _reviewLast,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text('Review last take'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_latest != null)
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      title: Text('Last score: ${_latest!.score.toStringAsFixed(0)}'),
                      subtitle: Text('Completed ${_latest!.dateLabel}'),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _startExercise() async {
    final opened = ExerciseRouteRegistry.open(context, widget.exerciseId);
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exercise not wired yet')),
      );
      return;
    }
    await Future.delayed(const Duration(milliseconds: 300));
    await _attempts.refresh();
    final latest = _attempts.latestFor(widget.exerciseId);
    if (mounted) {
      setState(() => _latest = latest == null ? null : ExerciseAttemptInfo.fromAttempt(latest));
    }
  }

  void _reviewLast() {
    final ex = _exercise;
    final attempt = _latest;
    if (ex == null || attempt == null || attempt.recordingPath == null || attempt.recordingPath!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No previous recording available')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseReviewScreen(exercise: ex, attempt: attempt.raw),
      ),
    );
  }

  Future<void> _playPreview(VocalExercise ex) async {
    setState(() => _previewing = true);
    try {
      // If we have a highway spec, render a short preview. Otherwise show message.
      if (ex.highwaySpec == null || ex.highwaySpec!.segments.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No preview available for this exercise')),
        );
        return;
      }
      // Use synth to render a short preview from the first few segments.
      final segments = ex.highwaySpec!.segments.take(8).toList();
      final notes = segments
          .take(8)
          .map((s) => ReferenceNote(
                startSec: s.startMs / 1000.0,
                endSec: s.endMs / 1000.0,
                midi: s.midiNote,
              ))
          .toList();
      final totalDurationMs =
          segments.isEmpty ? 0 : segments.map((s) => s.endMs).reduce(math.max) - segments.first.startMs;
      final path = await _synth.renderReferenceNotes(notes);
      await _synth.playFile(path);
      // Ensure the button stays in the "playing" state for the full preview duration.
      if (totalDurationMs > 0) {
        await Future.delayed(Duration(milliseconds: totalDurationMs + 300));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preview failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }
}

class _Header extends StatelessWidget {
  final VocalExercise ex;
  const _Header({required this.ex});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(ex.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Row(
          children: [
            Chip(label: Text(ex.categoryId)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ex.description,
                style: Theme.of(context).textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 140,
          child: BannerCard(
            title: ex.name,
            subtitle: ex.description,
            bannerStyleId: ex.categoryId.hashCode % 5,
          ),
        ),
      ],
    );
  }
}

class ExerciseAttemptInfo {
  final double score;
  final DateTime completedAt;
  final String? recordingPath;
  final ExerciseAttempt raw;

  ExerciseAttemptInfo({
    required this.score,
    required this.completedAt,
    required this.recordingPath,
    required this.raw,
  });

  factory ExerciseAttemptInfo.fromAttempt(ExerciseAttempt attempt) {
    return ExerciseAttemptInfo(
      score: attempt.overallScore,
      completedAt: attempt.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      recordingPath: attempt.recordingPath,
      raw: attempt,
    );
  }

  String get dateLabel {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(completedAt.year, completedAt.month, completedAt.day);
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    return '${_month(completedAt.month)} ${completedAt.day}';
  }

  String _month(int m) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (m < 1 || m > 12) return '';
    return names[m - 1];
  }
}
