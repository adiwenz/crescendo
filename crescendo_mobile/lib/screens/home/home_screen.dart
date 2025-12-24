import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/home/gradient_feature_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Temporary in-memory completion state
  // TODO: Connect to SQLite/database later
  final Set<String> _completedIds = {'lip_trills', 'sirens'};
  
  // All exercise IDs for today
  static const List<String> _allExerciseIds = [
    'lip_trills',
    'sirens',
    'vocal_scales',
    'breathing',
    'range_building',
  ];

  void _toggleCompletion(String id) {
    setState(() {
      if (_completedIds.contains(id)) {
        _completedIds.remove(id);
      } else {
        _completedIds.add(id);
      }
    });
  }
  
  bool get _isComplete {
    return _completedIds.length == _allExerciseIds.length;
  }
  
  int get _completedCount => _completedIds.length;
  
  int get _totalCount => _allExerciseIds.length;

  @override
  Widget build(BuildContext context) {

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark, // Dark status bar content
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withOpacity(0.95), // Faint cool white at top
                const Color(0xFFFFF4F6), // Soft cream/blush
                const Color(0xFFFBEAEC), // Soft peach
              ],
              stops: const [0.0, 0.3, 1.0],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                // Scrollable content
                SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
            Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.04),
                            // Good morning text
                            const Text(
                              'Good morning',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2E2E2E),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Let\'s train your voice',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF7A7A7A),
                              ),
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.03),
                            // Today's Intention title
                            const Text(
                              'Today\'s Intention',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2E2E2E),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Smooth transitions gradient card
                            GradientFeatureBar(
                              title: 'Smooth transitions through your passagio',
                              icon: Icons.favorite,
                              onTap: () {},
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.03),
                            // Today's Exercises title with progress
                            Builder(
                              builder: (context) {
                                // Count completed exercises (first 3: lip_trills, sirens, vocal_scales)
                                final completedCount = [
                                  'lip_trills',
                                  'sirens',
                                  'vocal_scales'
                                ].where((id) => _completedIds.contains(id)).length;
                                return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Text(
                                      'Today\'s Exercises',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF2E2E2E),
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                                        Text(
                                          '$completedCount of 3 complete',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: const Color(0xFF7A7A7A),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '8min',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w400,
                                            color: const Color(0xFFA5A5A5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                  ),
                  const SizedBox(height: 12),
                            // Daily exercises - individual cards with timeline
                            Stack(
                              children: [
                                // Timeline line on the left (connecting all cards)
                                Positioned(
                                  left: 12,
                                  top: 12,
                                  bottom: 12,
                                  child: Container(
                                    width: 2,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF7FD1B9), // Teal
                                      borderRadius: BorderRadius.circular(1),
                                    ),
                                  ),
                                ),
                                // Individual exercise cards
                                Column(
                      children: [
                                    _ExerciseCard(
                                      exerciseId: 'lip_trills',
                                      title: 'Lip Trills',
                                      level: 'Level 1',
                                      categoryIcon: Icons.local_fire_department,
                                      categoryColor: const Color(0xFF7FD1B9), // Mint/teal
                                      isCompleted: _completedIds.contains('lip_trills'),
                                      onTap: () => _toggleCompletion('lip_trills'),
                                    ),
                                    const SizedBox(height: 10),
                                    _ExerciseCard(
                                      exerciseId: 'sirens',
                                      title: 'Sirens',
                                      level: 'Level 2',
                                      categoryIcon: Icons.speed,
                                      categoryColor: const Color(0xFFF1D27A), // Butter yellow
                                      isCompleted: _completedIds.contains('sirens'),
                                      onTap: () => _toggleCompletion('sirens'),
                                    ),
                                    const SizedBox(height: 10),
                                    _ExerciseCard(
                                      exerciseId: 'vocal_scales',
                                      title: 'Vocal Scales',
                                      level: 'Level 1',
                                      categoryIcon: Icons.library_music,
                                      categoryColor: const Color(0xFFB9B6F3), // Pastel lavender
                                      isCompleted: _completedIds.contains('vocal_scales'),
                                      onTap: () => _toggleCompletion('vocal_scales'),
                                    ),
                                    const SizedBox(height: 10),
                                    _ExerciseCard(
                                      exerciseId: 'breathing',
                                      title: 'Breathing Exercises',
                                      level: 'Level 2',
                                      categoryIcon: Icons.tune,
                                      categoryColor: const Color(0xFFF3B7A6), // Soft peach
                                      isCompleted: _completedIds.contains('breathing'),
                                      onTap: () => _toggleCompletion('breathing'),
                                    ),
                                    const SizedBox(height: 10),
                                    _ExerciseCard(
                                      exerciseId: 'range_building',
                                      title: 'Range Building',
                                      level: 'Level 1',
                                      categoryIcon: Icons.trending_up,
                                      categoryColor: const Color(0xFFF1D27A), // Butter yellow
                                      isCompleted: _completedIds.contains('range_building'),
                                      onTap: () => _toggleCompletion('range_building'),
                                    ),
                                  ],
                          ),
                      ],
                    ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.04),
                          ],
                        ),
                      ),
                      // Status affirmation band (last item in scroll) - full width, outside padding
                      _StatusAffirmationBand(
                        isComplete: _isComplete,
                        completedCount: _completedCount,
                        totalCount: _totalCount,
                      ),
                      SizedBox(height: MediaQuery.of(context).size.height * 0.02),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final String exerciseId;
  final String title;
  final String level;
  final IconData categoryIcon;
  final Color categoryColor;
  final bool isCompleted;
  final VoidCallback onTap;

  const _ExerciseCard({
    required this.exerciseId,
    required this.title,
    required this.level,
    required this.categoryIcon,
    required this.categoryColor,
    required this.isCompleted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: const Color(0xFFE6E1DC).withOpacity(0.6),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 24,
              spreadRadius: 0,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Checkmark circle area
            SizedBox(
              width: 28,
              child: _ExerciseCheckmark(isCompleted: isCompleted),
            ),
            const SizedBox(width: 16),
            // Exercise text and level
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                    children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF2E2E2E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    level,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF7A7A7A),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Category icon on the right (centered vertically, moved left)
            Icon(
              categoryIcon,
              size: 28,
              color: categoryColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusAffirmationBand extends StatelessWidget {
  final bool isComplete;
  final int completedCount;
  final int totalCount;

  const _StatusAffirmationBand({
    required this.isComplete,
    required this.completedCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final messages = isComplete
        ? [
            'Nice work today!',
            'Great job completing your exercises!',
            'You\'re doing amazing!',
          ]
        : [
            'Keep going, you\'ve got this!',
            'You\'re making progress!',
            'Every step counts!',
          ];
    
    final message = messages[completedCount % messages.length];
    final icon = isComplete ? Icons.check_circle_outline : Icons.favorite_outline;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFE6E1DC).withOpacity(0.3),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: const Color(0xFF7FD1B9).withOpacity(0.7), // Muted mint
          ),
          const SizedBox(width: 8),
          Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Color(0xFF8E8E93), // Muted gray
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseCheckmark extends StatelessWidget {
  final bool isCompleted;

  const _ExerciseCheckmark({required this.isCompleted});

  @override
  Widget build(BuildContext context) {
    const size = 24.0;

    if (isCompleted) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFF7FD1B9), // Mint/teal
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.check,
          size: 16,
          color: Colors.white,
        ),
      );
    } else {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFFD1D1D6),
            width: 2,
          ),
        ),
      );
    }
  }
}
