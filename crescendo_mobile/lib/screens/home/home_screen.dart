import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/home/floating_accent.dart';
import '../../widgets/home/gradient_feature_bar.dart';
import '../../widgets/home/home_bar_card.dart';
import '../../widgets/home/timeline_track.dart';
import '../../widgets/home/vocal_warmup_item.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Temporary in-memory completion state
  // TODO: Connect to SQLite/database later
  final Set<String> _completedIds = {'lip_trills', 'sirens', 'vocal_scales'};

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
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final centerX = screenWidth / 2;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark, // Dark status bar content
      child: Scaffold(
        body: Container(
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
                // Scrollable content with timeline
                SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: Stack(
                    children: [
                      // Centered vertical timeline
                      Positioned(
                        left: centerX - 1,
                        top: 0,
                        bottom: 0,
                        child: CustomPaint(
                          painter: TimelineTrack(
                            width: 2,
                            height: 2000, // Large enough for scroll
                            segments: [
                              TimelineSegment(
                                length: 120, // Top spacing
                                color: const Color(0xFF7FD1B9), // Teal
                                isDashed: false,
                              ),
                              TimelineSegment(
                                length: 80, // After first exercise
                                color: const Color(0xFF7FD1B9), // Teal
                                isDashed: false,
                                hasNode: true,
                              ),
                              TimelineSegment(
                                length: 80, // After second exercise
                                color: const Color(0xFF7FD1B9), // Teal
                                isDashed: false,
                                hasNode: true,
                              ),
                              TimelineSegment(
                                length: 80, // After third exercise
                                color: const Color(0xFF7FD1B9), // Teal
                                isDashed: false,
                                hasNode: true,
                              ),
                              TimelineSegment(
                                length: 40, // Transition space
                                color: const Color(0xFFF3B7A6), // Orange/peach
                                isDashed: true,
                              ),
                              TimelineSegment(
                                length: 100, // After Breathing Techniques
                                color: const Color(0xFFF3B7A6), // Orange/peach
                                isDashed: false,
                              ),
                              TimelineSegment(
                                length: 100, // After Stretch & Relax
                                color: const Color(0xFFF3B7A6), // Orange/peach
                                isDashed: false,
                              ),
                              TimelineSegment(
                                length: 100, // After Stats & Insights
                                color: const Color(0xFFF3B7A6), // Orange/peach
                                isDashed: false,
                              ),
                              TimelineSegment(
                                length: 100, // After Calendar & Notes
                                color: const Color(0xFFF3B7A6), // Orange/peach
                                isDashed: false,
                              ),
                              TimelineSegment(
                                length: 200, // Bottom spacing
                                color: const Color(0xFFF3B7A6), // Orange/peach
                                isDashed: true,
                              ),
                            ],
                          ),
                          size: const Size(2, 2000),
                        ),
                      ),
                      // Content
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            const SizedBox(height: 40),
                            // Today's Vocal Warmup section
                            const Padding(
                              padding: EdgeInsets.only(bottom: 16),
                              child: Text(
                                'Today\'s Vocal Warmup',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF2E2E2E),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Lip Trills
                            VocalWarmupItem(
                              title: 'Lip Trills',
                              isCompleted: _completedIds.contains('lip_trills'),
                              onTap: () => _toggleCompletion('lip_trills'),
                            ),
                            const SizedBox(height: 12),
                            // Sirens
                            VocalWarmupItem(
                              title: 'Sirens',
                              isCompleted: _completedIds.contains('sirens'),
                              onTap: () => _toggleCompletion('sirens'),
                            ),
                            const SizedBox(height: 12),
                            // Vocal Scales
                            VocalWarmupItem(
                              title: 'Vocal Scales',
                              isCompleted: _completedIds.contains('vocal_scales'),
                              onTap: () => _toggleCompletion('vocal_scales'),
                            ),
                            const SizedBox(height: 40),
                            // Breathing Techniques
                            HomeBarCard(
                              onTap: () {},
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Breathing Techniques',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF2E2E2E),
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 20,
                                    color: Color(0xFFA5A5A5),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Stretch & Relax (gradient feature bar)
                            GradientFeatureBar(
                              title: 'Stretch & Relax',
                              icon: Icons.favorite,
                              onTap: () {},
                            ),
                            const SizedBox(height: 20),
                            // Stats & Insights (slightly right of center)
                            HomeBarCard(
                              alignment: Alignment.centerRight,
                              width: screenWidth * 0.85,
                              onTap: () {},
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.chat_bubble_outline,
                                        size: 20,
                                        color: Color(0xFFB9B6F3), // Purple
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        'Stats & Insights',
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF2E2E2E),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 20,
                                    color: Color(0xFFA5A5A5),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Calendar & Notes
                            Stack(
                              children: [
                                HomeBarCard(
                                  onTap: () {},
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.calendar_today,
                                            size: 20,
                                            color: Color(0xFFB9B6F3), // Purple
                                          ),
                                          SizedBox(width: 12),
                                          Text(
                                            'Calendar & Notes',
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFF2E2E2E),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                // Orange capsule button floating on right
                                Positioned(
                                  right: -12,
                                  top: 0,
                                  bottom: 0,
                                  child: Center(
                                    child: OrangeCapsuleButton(
                                      onTap: () {},
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            // Bottom gradient pill bar
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Color(0xFFF4A3C4), // Blush pink
                                    Color(0xFFF1D27A), // Butter yellow
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.06),
                                    blurRadius: 24,
                                    spreadRadius: 0,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Calendar & Notes',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF2E2E2E),
                                    ),
                                  ),
                                  Icon(
                                    Icons.person_outline,
                                    size: 20,
                                    color: Color(0xFF2E2E2E),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 60),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Floating accents (positioned relative to screen)
                // Pink gradient square (right side mid-screen)
                Positioned(
                  right: 20,
                  top: screenHeight * 0.4,
                  child: const PinkGradientSquare(),
                ),
                // Purple chat bubble (left side)
                Positioned(
                  left: 20,
                  top: screenHeight * 0.5,
                  child: const PurpleChatBubble(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
