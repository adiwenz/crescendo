import 'package:flutter/material.dart';

import '../../models/exercise_category.dart';
import '../../models/vocal_exercise.dart';
import '../../services/exercise_repository.dart';
import '../../services/attempt_repository.dart';
import '../../state/library_store.dart';
import '../../widgets/exercise_row_banner.dart';
import 'exercise_preview_screen.dart';

class CategoryDetailScreen extends StatefulWidget {
  final ExerciseCategory category;
  final int? initialCategoryIndex;

  const CategoryDetailScreen({
    super.key,
    required this.category,
    this.initialCategoryIndex,
  });

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ExerciseRepository _exerciseRepo = ExerciseRepository();
  final AttemptRepository _attempts = AttemptRepository.instance;
  List<ExerciseCategory> _categories = [];

  @override
  void initState() {
    super.initState();
    _categories = _exerciseRepo.getCategories();
    final initialIndex = widget.initialCategoryIndex ?? 
        _categories.indexWhere((c) => c.id == widget.category.id);
    _tabController = TabController(
      length: _categories.length,
      initialIndex: initialIndex >= 0 ? initialIndex : 0,
      vsync: this,
    );
    _tabController.addListener(_onTabChanged);
    _attempts.addListener(_onAttemptsChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _attempts.removeListener(_onAttemptsChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    setState(() {}); // Update header title when tab changes
  }

  void _onAttemptsChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header with back button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      _categories[_tabController.index].title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
            ),
            // Horizontal category selector (swipeable)
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
                onTap: (index) {
                  setState(() {}); // Update header title
                },
                tabs: _categories.map((category) {
                  return Tab(text: category.title);
                }).toList(),
              ),
            ),
            // Exercise list (swipeable between categories)
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
