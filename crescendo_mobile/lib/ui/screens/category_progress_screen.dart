import 'package:flutter/material.dart';

import '../../models/exercise_category.dart';
import '../../models/exercise_attempt.dart';
import '../../models/vocal_exercise.dart';
import '../../services/exercise_repository.dart';
import '../../services/attempt_repository.dart';
import 'exercise_progress_detail_screen.dart';

class CategoryProgressScreen extends StatefulWidget {
  final ExerciseCategory category;

  const CategoryProgressScreen({super.key, required this.category});

  @override
  State<CategoryProgressScreen> createState() => _CategoryProgressScreenState();
}

class _CategoryProgressScreenState extends State<CategoryProgressScreen> {
  final ExerciseRepository _exerciseRepo = ExerciseRepository();
  final AttemptRepository _attempts = AttemptRepository.instance;
  List<VocalExercise> _exercises = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadExercises();
    _attempts.addListener(_onAttemptsChanged);
  }

  @override
  void dispose() {
    _attempts.removeListener(_onAttemptsChanged);
    super.dispose();
  }

  void _onAttemptsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadExercises() async {
    final exercises = _exerciseRepo.getExercisesForCategory(widget.category.id);
    // Only ensure loaded, don't refresh - use cache which is already up to date
    await _attempts.ensureLoaded();
    if (mounted) {
      setState(() {
        _exercises = exercises;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.category.title),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _exercises.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No exercises yet in this category.',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Colors.grey[600],
                              ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _exercises.length,
                  itemBuilder: (context, index) {
                    final exercise = _exercises[index];
                    final latestAttempt = _attempts.latestFor(exercise.id);

                    return _ExerciseProgressItem(
                      exercise: exercise,
                      latestAttempt: latestAttempt,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ExerciseProgressDetailScreen(exercise: exercise),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}

class _ExerciseProgressItem extends StatelessWidget {
  final VocalExercise exercise;
  final ExerciseAttempt? latestAttempt;
  final VoidCallback onTap;

  const _ExerciseProgressItem({
    required this.exercise,
    this.latestAttempt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final score = latestAttempt?.overallScore;
    final date = latestAttempt?.completedAt ?? latestAttempt?.startedAt;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (score != null || date != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (score != null) 'Latest: ${score.toStringAsFixed(0)}%',
                          if (date != null) _formatDate(date),
                        ].join(' • '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);
    if (dateOnly == today) return 'Today';
    if (dateOnly == yesterday) return 'Yesterday';
    return '${_month(date.month)} ${date.day}';
  }

  String _month(int m) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (m < 1 || m > 12) return '';
    return names[m - 1];
  }
}
