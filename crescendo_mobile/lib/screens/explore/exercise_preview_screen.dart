import 'package:flutter/material.dart';

import '../../models/vocal_exercise.dart';
import '../../models/exercise_attempt.dart';
import '../../routing/exercise_route_registry.dart';
import '../../services/attempt_repository.dart';
import '../../services/exercise_repository.dart';
import '../../widgets/banner_card.dart';

class ExercisePreviewScreen extends StatefulWidget {
  final String exerciseId;

  const ExercisePreviewScreen({super.key, required this.exerciseId});

  @override
  State<ExercisePreviewScreen> createState() => _ExercisePreviewScreenState();
}

class _ExercisePreviewScreenState extends State<ExercisePreviewScreen> {
  final ExerciseRepository _repo = ExerciseRepository();
  final AttemptRepository _attempts = AttemptRepository.instance;
  VocalExercise? _exercise;
  ExerciseAttemptInfo? _latest;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ex = _repo.getExercises().firstWhere(
      (e) => e.id == widget.exerciseId,
      orElse: () => _repo.getExercises().first,
    );
    await _attempts.refresh();
    final latest = _attempts.latestFor(widget.exerciseId);
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
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Preview playback coming soon')),
                                );
                              },
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Play preview'),
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Review last take coming soon')),
    );
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

  ExerciseAttemptInfo({required this.score, required this.completedAt});

  factory ExerciseAttemptInfo.fromAttempt(ExerciseAttempt attempt) {
    return ExerciseAttemptInfo(
      score: attempt.overallScore,
      completedAt: attempt.completedAt,
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
