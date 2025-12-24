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

  void _toggleCompletion(String id) {
    setState(() {
      if (_completedIds.contains(id)) {
        _completedIds.remove(id);
      } else {
        _completedIds.add(id);
      }
    });
  }

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
                  child: Padding(
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
                            // Daily exercises - single clickable card with timeline
                            Container(
                              padding: const EdgeInsets.all(20),
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
                              child: Stack(
                                children: [
                                  // Timeline line on the left
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
                                  // Exercise items
                                  Column(
                                    children: [
                                      InkWell(
                                        onTap: () => _toggleCompletion('lip_trills'),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Checkmark circle area
                                              SizedBox(
                                                width: 28,
                                                child: _ExerciseCheckmark(
                                                  isCompleted: _completedIds
                                                      .contains('lip_trills'),
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              // Exercise text and level
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                                                    Text(
                                                      'Lip Trills',
                                                      style: const TextStyle(
                                                        fontSize: 17,
                                                        fontWeight: FontWeight.w500,
                                                        color: Color(0xFF2E2E2E),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Level 1',
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w400,
                                                        color: const Color(0xFF7A7A7A),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (_completedIds
                                                  .contains('lip_trills'))
                                                const Icon(
                                                  Icons.check,
                                                  size: 20,
                                                  color: Color(0xFFA5A5A5),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      InkWell(
                                        onTap: () => _toggleCompletion('sirens'),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Checkmark circle area
                  SizedBox(
                                                width: 28,
                                                child: _ExerciseCheckmark(
                                                  isCompleted: _completedIds
                                                      .contains('sirens'),
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              // Exercise text and level
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                                                    Text(
                                                      'Sirens',
                                                      style: const TextStyle(
                                                        fontSize: 17,
                                                        fontWeight: FontWeight.w500,
                                                        color: Color(0xFF2E2E2E),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Level 2',
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w400,
                                                        color: const Color(0xFF7A7A7A),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (_completedIds.contains('sirens'))
                                                const Icon(
                                                  Icons.check,
                                                  size: 20,
                                                  color: Color(0xFFA5A5A5),
                          ),
                      ],
                    ),
                  ),
                                      ),
                                      const SizedBox(height: 8),
                                      InkWell(
                                        onTap: () => _toggleCompletion('vocal_scales'),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Checkmark circle area
                                              SizedBox(
                                                width: 28,
                                                child: _ExerciseCheckmark(
                                                  isCompleted: _completedIds
                                                      .contains('vocal_scales'),
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              // Exercise text and level
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                                                    Text(
                                                      'Vocal Scales',
                                                      style: const TextStyle(
                                                        fontSize: 17,
                                                        fontWeight: FontWeight.w500,
                                                        color: Color(0xFF2E2E2E),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Level 1',
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w400,
                                                        color: const Color(0xFF7A7A7A),
              ),
            ),
          ],
        ),
      ),
                                              if (_completedIds
                                                  .contains('vocal_scales'))
                                                const Icon(
                                                  Icons.check,
                                                  size: 20,
                                                  color: Color(0xFFA5A5A5),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      InkWell(
                                        onTap: () => _toggleCompletion('breathing'),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Checkmark circle area
                                              SizedBox(
                                                width: 28,
                                                child: _ExerciseCheckmark(
                                                  isCompleted: _completedIds
                                                      .contains('breathing'),
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              // Exercise text and level
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Breathing Exercises',
                                                      style: const TextStyle(
                                                        fontSize: 17,
                                                        fontWeight: FontWeight.w500,
                                                        color: Color(0xFF2E2E2E),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Level 2',
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w400,
                                                        color: const Color(0xFF7A7A7A),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (_completedIds.contains('breathing'))
                                                const Icon(
                                                  Icons.check,
                                                  size: 20,
                                                  color: Color(0xFFA5A5A5),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      InkWell(
                                        onTap: () => _toggleCompletion('range_building'),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Checkmark circle area
                                              SizedBox(
                                                width: 28,
                                                child: _ExerciseCheckmark(
                                                  isCompleted: _completedIds
                                                      .contains('range_building'),
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              // Exercise text and level
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Range Building',
                                                      style: const TextStyle(
                                                        fontSize: 17,
                                                        fontWeight: FontWeight.w500,
                                                        color: Color(0xFF2E2E2E),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Level 1',
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w400,
                                                        color: const Color(0xFF7A7A7A),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (_completedIds
                                                  .contains('range_building'))
                                                const Icon(
                                                  Icons.check,
                                                  size: 20,
                                                  color: Color(0xFFA5A5A5),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: MediaQuery.of(context).size.height * 0.04),
                      ],
                    ),
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
