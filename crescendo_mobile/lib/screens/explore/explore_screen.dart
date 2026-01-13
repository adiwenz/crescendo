import 'package:flutter/material.dart';

import '../../services/exercise_repository.dart';
import '../../models/exercise_category.dart';
import '../../models/vocal_exercise.dart';
import '../../widgets/exercise_row_banner.dart';
import '../../state/library_store.dart';
import '../../services/attempt_repository.dart';
import 'exercise_preview_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ExerciseRepository _exerciseRepo = ExerciseRepository();
  final AttemptRepository _attempts = AttemptRepository.instance;
  List<ExerciseCategory> _categories = [];

  @override
  void initState() {
    super.initState();
    _categories = _exerciseRepo.getCategories();
    _tabController = TabController(
      length: _categories.length,
      vsync: this,
    );
    _tabController.addListener(_onTabChanged);
    _attempts.refresh();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    // Tab change is handled automatically by TabBarView
    // This listener can be used for additional logic if needed
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Explore',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
            ),
            // Horizontal category selector (sticky)
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Colors.black54,
                indicatorColor: Theme.of(context).colorScheme.primary,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 14,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                tabs: _categories.map((category) {
                  return Tab(text: category.title);
                }).toList(),
              ),
            ),
            // Exercise list (swipeable)
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _categories.map((category) {
                  return _ExerciseListForCategory(category: category);
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseListForCategory extends StatefulWidget {
  final ExerciseCategory category;

  const _ExerciseListForCategory({required this.category});

  @override
  State<_ExerciseListForCategory> createState() =>
      _ExerciseListForCategoryState();
}

class _ExerciseListForCategoryState extends State<_ExerciseListForCategory> {
  final ExerciseRepository _exerciseRepo = ExerciseRepository();
  final AttemptRepository _attempts = AttemptRepository.instance;
  List<VocalExercise> _exercises = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  Future<void> _loadExercises() async {
    final exercises = _exerciseRepo.getExercisesForCategory(widget.category.id);
    await _attempts.refresh();
    if (mounted) {
      setState(() {
        _exercises = exercises;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final completedIds = _attempts.cache
        .map((a) => a.exerciseId)
        .toSet()
      ..addAll(libraryStore.completedExerciseIds);

    if (_exercises.isEmpty) {
      return Center(
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
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _exercises.length,
      itemBuilder: (context, index) {
        final exercise = _exercises[index];
        final isCompleted = completedIds.contains(exercise.id);
        // Map categoryId to bannerStyleId for consistent colors
        final bannerStyleId = exercise.categoryId.hashCode.abs() % 8;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ExerciseRowBanner(
            title: exercise.name,
            subtitle: exercise.description,
            bannerStyleId: bannerStyleId,
            completed: isCompleted,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExercisePreviewScreen(exerciseId: exercise.id),
                ),
              );
              await _attempts.refresh();
              await libraryStore.load();
              if (mounted) {
                setState(() {});
              }
            },
          ),
        );
      },
    );
  }
}
