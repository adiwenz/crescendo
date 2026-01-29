import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../design/styles.dart';
import 'explore/exercise_preview_screen.dart';

// Debug toggle - set to false once layout matches target
const bool kDebugLayout = false;

// Timeline Exercise Model
class TimelineExercise {
  final String id;
  final String name; // label shown in circle
  final String description; // shown at bottom
  final int level;
  final int minutes;
  bool completed; // Made mutable for state updates

  TimelineExercise({
    required this.id,
    required this.name,
    required this.description,
    required this.level,
    required this.minutes,
    this.completed = false,
  });

  TimelineExercise copyWith({bool? completed}) {
    return TimelineExercise(
      id: id,
      name: name,
      description: description,
      level: level,
      minutes: minutes,
      completed: completed ?? this.completed,
    );
  }
}

class TimelineLaunchScreen extends StatefulWidget {
  const TimelineLaunchScreen({super.key});

  @override
  State<TimelineLaunchScreen> createState() => _TimelineLaunchScreenState();
}

class _TimelineLaunchScreenState extends State<TimelineLaunchScreen> {
  // Today's ordered list from top to bottom on the arc
  late List<TimelineExercise> _exercises;
  String? _selectedExerciseId; // Track selected exercise
  TimelineExercise? _lastSelectedExercise; // Track last selected for fade out

  @override
  void initState() {
    super.initState();
    // Initialize with sample data
    _exercises = [
      TimelineExercise(
        id: 'agility',
        name: 'Agility',
        description:
            'Gentle warmup exercises to prepare your voice for practice. Focus on relaxed breathing and smooth transitions.',
        level: 1,
        minutes: 5,
        completed: true,
      ),
      TimelineExercise(
        id: 'sirens',
        name: 'Sirens',
        description:
            'Sirens help you explore your full vocal range smoothly. Start from your lowest comfortable note and glide up to your highest, then back down.',
        level: 1,
        minutes: 5,
        completed: true,
      ),
      TimelineExercise(
        id: 'slides',
        name: 'Slides',
        description:
            'Pitch slides build accuracy and vocal flexibility. Practice smooth ascending and descending slides across your range.',
        level: 1,
        minutes: 5,
        completed: true,
      ),
      TimelineExercise(
        id: 'breathing',
        name: 'Breathing',
        description:
            'Proper breathing is the foundation of good vocal technique. Learn to control your breath and support your voice with diaphragmatic breathing exercises.',
        level: 1,
        minutes: 10,
        completed: false, // This is the "next" exercise
      ),
      TimelineExercise(
        id: 'take-10',
        name: 'Warmup',
        description: 'Continue your practice with focused exercises.',
        level: 1,
        minutes: 10,
        completed: false,
      ),
    ];

    // Don't auto-select any exercise on load
    _selectedExerciseId = null;
  }

  // Get the next exercise (first incomplete)
  TimelineExercise? _getNextExercise() {
    for (final exercise in _orderedExercises) {
      if (!exercise.completed) {
        return exercise;
      }
    }
    return _orderedExercises.last; // Fallback to last if all completed
  }

  // Get selected exercise
  TimelineExercise? _getSelectedExercise() {
    if (_selectedExerciseId == null) return null;
    try {
      return _exercises.firstWhere((e) => e.id == _selectedExerciseId);
    } catch (e) {
      return _getNextExercise();
    }
  }

  // Select an exercise (does not start it)
  void _selectExercise(String exerciseId) {
    setState(() {
      // Store the current selection before changing
      if (_selectedExerciseId != null) {
        _lastSelectedExercise = _getSelectedExercise();
      }
      // Toggle selection - if clicking the same exercise, deselect it
      if (_selectedExerciseId == exerciseId) {
        _selectedExerciseId = null;
        // Clear last selected after fade out completes
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted && _selectedExerciseId == null) {
            setState(() {
              _lastSelectedExercise = null;
            });
          }
        });
      } else {
        _selectedExerciseId = exerciseId;
        _lastSelectedExercise = null; // Clear when selecting new one
      }
    });
  }

  // Get exercises in order: [exercise4, exercise3, exercise2, nextExercise, takeExercise]
  List<TimelineExercise> get _orderedExercises => [
        _exercises[0], // exercise4 (Warmup)
        _exercises[1], // exercise3 (Sirens)
        _exercises[2], // exercise2 (Slides)
        _exercises[3], // nextExercise (Breathing)
        _exercises[4], // takeExercise (TAKE)
      ];

  Future<void> _startExercise(TimelineExercise exercise) async {
    // Navigate to exercise preview
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExercisePreviewScreen(exerciseId: exercise.id),
      ),
    );

    // When exercise completes, return to Home
    if (mounted && result != null) {
      // Mark as completed
      final index = _exercises.indexWhere((e) => e.id == exercise.id);
      if (index != -1) {
        setState(() {
          _exercises[index] = _exercises[index].copyWith(completed: true);

          // Auto-select the next incomplete exercise
          final newNext = _getNextExercise();
          if (newNext != null) {
            _selectedExerciseId = newNext.id;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final safeAreaTop = MediaQuery.of(context).padding.top;
    final W = screenWidth;
    final H = screenHeight;

    // Gold block boundaries
    final goldTop = safeAreaTop + 84;
    final goldHeight = 0.52 * H;
    final goldBottom = goldTop + goldHeight;

    // Hard anchor points (global coordinates)
    final n4 = Offset(0.40 * W, goldTop + 0.14 * goldHeight);
    final n3 = Offset(0.30 * W, goldTop + 0.30 * goldHeight);
    final n2 = Offset(0.24 * W, goldTop + 0.48 * goldHeight);
    final play = Offset(0.34 * W, goldTop + 0.73 * goldHeight);
    final take = Offset(0.57 * W, goldBottom + 0.02 * H);

    // Node radii
    const smallR = 30.0;
    const nextR = 50.0; // Large next exercise circle
    const takeR = 54.0;

    final nextExercise = _getNextExercise();
    final selectedExercise =
        _getSelectedExercise() ?? nextExercise ?? _orderedExercises.first;
    // Find the last completed exercise (or first if none completed)
    TimelineExercise? currentExercise;
    for (int i = _orderedExercises.length - 1; i >= 0; i--) {
      if (_orderedExercises[i].completed) {
        currentExercise = _orderedExercises[i];
        break;
      }
    }
    currentExercise ??= _orderedExercises.first;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Stack(
          children: [
            // Background: Gradient + Gold block + Off-white
            Column(
              children: [
                // Top bar with gradient background
                Container(
                  decoration: const BoxDecoration(
                    gradient: AppStyles.welcomeBackgroundGradient,
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Hamburger icon
                              IconButton(
                                icon: const Icon(Icons.menu,
                                    color: AppStyles.textSecondary),
                                onPressed: () {},
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              // Title with underline
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'WELCOME',
                                    style: AppStyles.appBarTitle,
                                  ),
                                  const SizedBox(height: 6),
                                  // Faint gray line under "Welcome"
                                  Container(
                                    width:
                                        80, // Approximate width of "Welcome" text
                                    height: 1,
                                    color: AppStyles.textSecondary
                                        .withOpacity(0.2),
                                  ),
                                ],
                              ),
                              // Help/info icon
                              IconButton(
                                icon: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: AppStyles.border,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.help_outline,
                                    size: 18,
                                    color: AppStyles.textSecondary,
                                  ),
                                ),
                                onPressed: () {},
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Middle section with gradient
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: AppStyles.welcomeMiddleGradient,
                    ),
                  ),
                ),
              ],
            ),

            // Exercise name on the right side when selected (behind colorful circles)
            Positioned(
              right: (screenWidth - (take.dx + takeR + 100)) /
                  2, // Centered between circles and right edge
              top: MediaQuery.of(context).size.height *
                  0.30, // Moved slightly up
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 800),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: child,
                  );
                },
                child: _selectedExerciseId != null
                    ? _AppearingExerciseNames(
                        key: ValueKey(_selectedExerciseId),
                        exercise: selectedExercise,
                      )
                    : _lastSelectedExercise != null
                        ? _AppearingExerciseNames(
                            key: ValueKey('last-${_lastSelectedExercise!.id}'),
                            exercise: _lastSelectedExercise!,
                          )
                        : const SizedBox.shrink(key: ValueKey('empty')),
              ),
            ),

            // Timeline arc and nodes overlay (on top of appearing circle)
            GestureDetector(
              onTap: () {
                // Deselect when tapping outside circles
                if (_selectedExerciseId != null) {
                  setState(() {
                    _selectedExerciseId = null;
                  });
                }
              },
              child: Stack(
                children: [
                  // Single smooth continuous curve through all points
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TimelineSplinePainter(
                        points: [n4, n3, n2, play, take],
                      ),
                    ),
                  ),

                  // Exercise 4 (top, rightmost) - completed
                  Positioned(
                    left: n4.dx - smallR,
                    top: n4.dy - smallR,
                    child: GestureDetector(
                      onTap: () {
                        if (_selectedExerciseId == _orderedExercises[0].id) {
                          _startExercise(_orderedExercises[0]);
                        } else {
                          _selectExercise(_orderedExercises[0].id);
                        }
                      },
                      child: AnimatedScale(
                        scale: _selectedExerciseId == _orderedExercises[0].id
                            ? 1.1
                            : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: _TimelineExerciseNode(
                          exercise: _orderedExercises[0],
                          size: smallR * 2,
                          color: AppStyles.timelineLightest, // Lightest
                          hasCheckBadge: true,
                          isSelected:
                              _selectedExerciseId == _orderedExercises[0].id,
                        ),
                      ),
                    ),
                  ),

                  // Exercise 3 (middle) - completed
                  Positioned(
                    left: n3.dx - smallR,
                    top: n3.dy - smallR,
                    child: GestureDetector(
                      onTap: () {
                        if (_selectedExerciseId == _orderedExercises[1].id) {
                          _startExercise(_orderedExercises[1]);
                        } else {
                          _selectExercise(_orderedExercises[1].id);
                        }
                      },
                      child: AnimatedScale(
                        scale: _selectedExerciseId == _orderedExercises[1].id
                            ? 1.1
                            : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: _TimelineExerciseNode(
                          exercise: _orderedExercises[1],
                          size: smallR * 2,
                          color: AppStyles.timelineMedium, // Medium
                          hasCheckBadge: true,
                          isSelected:
                              _selectedExerciseId == _orderedExercises[1].id,
                        ),
                      ),
                    ),
                  ),

                  // Exercise 2 (deepest left) - completed
                  Positioned(
                    left: n2.dx - smallR,
                    top: n2.dy - smallR,
                    child: GestureDetector(
                      onTap: () {
                        if (_selectedExerciseId == _orderedExercises[2].id) {
                          _startExercise(_orderedExercises[2]);
                        } else {
                          _selectExercise(_orderedExercises[2].id);
                        }
                      },
                      child: AnimatedScale(
                        scale: _selectedExerciseId == _orderedExercises[2].id
                            ? 1.1
                            : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: _TimelineExerciseNode(
                          exercise: _orderedExercises[2],
                          size: smallR * 2,
                          color: AppStyles.timelineDarker, // Darker
                          hasCheckBadge: true,
                          isSelected:
                              _selectedExerciseId == _orderedExercises[2].id,
                        ),
                      ),
                    ),
                  ),

                  // Next Exercise (large, primary focus) - at play position
                  Positioned(
                    left: play.dx - nextR,
                    top: play.dy - nextR,
                    child: GestureDetector(
                      onTap: () {
                        if (_selectedExerciseId == _orderedExercises[3].id) {
                          _startExercise(_orderedExercises[3]);
                        } else {
                          _selectExercise(_orderedExercises[3].id);
                        }
                      },
                      child: AnimatedScale(
                        scale: _selectedExerciseId == _orderedExercises[3].id
                            ? 1.15
                            : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          width: nextR * 2,
                          height: nextR * 2,
                          decoration: BoxDecoration(
                            gradient: AppStyles.timelineBeigeGradient,
                            shape: BoxShape.circle,
                            boxShadow:
                                _selectedExerciseId == _orderedExercises[3].id
                                    ? AppStyles.selectedCircleGlow
                                    : [
                                        BoxShadow(
                                          color: AppStyles.shadowColor,
                                          blurRadius: AppStyles.shadowBlur,
                                          offset: AppStyles.shadowOffset,
                                        ),
                                      ],
                          ),
                          child: Center(
                            child: _selectedExerciseId ==
                                    _orderedExercises[3].id
                                ? Icon(
                                    Icons.play_arrow,
                                    color: AppStyles.white,
                                    size: nextR * 0.8,
                                  )
                                : Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        _orderedExercises[3].name,
                                        textAlign: TextAlign.center,
                                        style:
                                            AppStyles.sectionHeading.copyWith(
                                          color: AppStyles.white,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Large TAKE circle
                  Positioned(
                    left: take.dx - takeR,
                    top: take.dy - takeR,
                    child: GestureDetector(
                      onTap: () {
                        if (_selectedExerciseId == _orderedExercises[4].id) {
                          _startExercise(_orderedExercises[4]);
                        } else {
                          _selectExercise(_orderedExercises[4].id);
                        }
                      },
                      child: AnimatedScale(
                        scale: _selectedExerciseId == _orderedExercises[4].id
                            ? 1.1
                            : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          width: takeR * 2,
                          height: takeR * 2,
                          decoration: BoxDecoration(
                            gradient: AppStyles.timelineDarkestGradient,
                            shape: BoxShape.circle,
                            boxShadow:
                                _selectedExerciseId == _orderedExercises[4].id
                                    ? AppStyles.selectedCircleGlow
                                    : null,
                          ),
                          child: Center(
                            child: _selectedExerciseId ==
                                    _orderedExercises[4].id
                                ? Icon(
                                    Icons.play_arrow,
                                    color: AppStyles.white,
                                    size: takeR * 0.8,
                                  )
                                : Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        _orderedExercises[4].name, // "TAKE"
                                        textAlign: TextAlign.center,
                                        style: AppStyles.headingMedium.copyWith(
                                          color: AppStyles.white,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Debug overlay (only when kDebugLayout is true)
                  if (kDebugLayout)
                    ..._buildDebugOverlay([n4, n3, n2, play, take], W),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDebugOverlay(List<Offset> points, double screenWidth) {
    final labels = ['n4', 'n3', 'n2', 'play', 'take'];
    return List.generate(points.length, (i) {
      return Positioned(
        left: points[i].dx - 5,
        top: points[i].dy - 5,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${labels[i]}\n(${points[i].dx.toStringAsFixed(0)}, ${points[i].dy.toStringAsFixed(0)})',
              style: const TextStyle(
                fontSize: 10,
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    });
  }
}

// Exercise name text on the right side of screen
class _AppearingExerciseNames extends StatelessWidget {
  final TimelineExercise exercise;

  const _AppearingExerciseNames({
    required this.exercise,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 800), // Longer fade in/out
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: Container(
        key: ValueKey(exercise.id),
        width: 220, // Bigger circle
        height: 220, // Bigger circle
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppStyles.white.withOpacity(0.2), // Translucent circle
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Exercise name - wrapped in FittedBox to fit inside circle
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                exercise.name,
                style: AppStyles.headingLarge.copyWith(
                  color: AppStyles.white
                      .withOpacity(0.9), // White, slightly translucent
                  fontWeight: FontWeight.w600,
                  fontSize: 32, // Keep font size the same
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            // Duration - same white color as text
            Text(
              '${exercise.minutes} min',
              style: AppStyles.body.copyWith(
                color: AppStyles.white.withOpacity(0.9), // Same white as text
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineExerciseNode extends StatelessWidget {
  final TimelineExercise exercise;
  final double size;
  final Color color;
  final bool hasCheckBadge;
  final bool isSelected;

  const _TimelineExerciseNode({
    required this.exercise,
    required this.size,
    required this.color,
    this.hasCheckBadge = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: AppStyles.getCircleGradient(color),
            shape: BoxShape.circle,
            boxShadow: isSelected ? AppStyles.selectedCircleGlow : null,
          ),
          child: Center(
            child: isSelected
                ? Icon(
                    Icons.play_arrow,
                    color: AppStyles.white,
                    size: size * 0.4,
                  )
                : Padding(
                    padding: const EdgeInsets.all(6),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        exercise.name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: exercise.completed
                              ? AppStyles.white
                              : AppStyles.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
          ),
        ),
        if (hasCheckBadge && exercise.completed)
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check,
                size: 12,
                color: AppStyles.timelineCheckIcon,
              ),
            ),
          ),
      ],
    );
  }
}

// Helper function to convert Catmull-Rom spline to cubic Bezier
Path _catmullRomToBezier(List<Offset> pts, {double tension = 0.5}) {
  assert(pts.length >= 2);
  final path = Path()..moveTo(pts[0].dx, pts[0].dy);

  for (int i = 0; i < pts.length - 1; i++) {
    final p0 = i == 0 ? pts[i] : pts[i - 1];
    final p1 = pts[i];
    final p2 = pts[i + 1];
    final p3 = (i + 2 < pts.length) ? pts[i + 2] : pts[i + 1];

    final c1 = Offset(
      p1.dx + (p2.dx - p0.dx) * tension / 6.0,
      p1.dy + (p2.dy - p0.dy) * tension / 6.0,
    );
    final c2 = Offset(
      p2.dx - (p3.dx - p1.dx) * tension / 6.0,
      p2.dy - (p3.dy - p1.dy) * tension / 6.0,
    );

    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path;
}

class _TimelineSplinePainter extends CustomPainter {
  final List<Offset> points;

  _TimelineSplinePainter({
    required this.points,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppStyles.timelineSpline // Muted gray-brown
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    if (points.length < 2) return;

    // Create smooth continuous curve through all points using Catmull-Rom spline
    final path = _catmullRomToBezier(points, tension: 0.5);

    // Draw single continuous path
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TimelineSplinePainter oldDelegate) {
    return oldDelegate.points != points;
  }
}
