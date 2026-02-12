import 'package:flutter/material.dart';
import '../../theme/ballad_theme.dart';
import '../../widgets/ballad_scaffold.dart';
import 'explore/exercise_preview_screen.dart';

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
  late List<TimelineExercise> _exercises;
  String? _selectedExerciseId; 
  TimelineExercise? _lastSelectedExercise;

  @override
  void initState() {
    super.initState();
    _exercises = [
      TimelineExercise(
        id: 'agility',
        name: 'Agility',
        description: 'Gentle warmup exercises to prepare your voice for practice.',
        level: 1,
        minutes: 5,
        completed: true,
      ),
      TimelineExercise(
        id: 'sirens',
        name: 'Sirens',
        description: 'Sirens help you explore your full vocal range smoothly.',
        level: 1,
        minutes: 5,
        completed: true,
      ),
      TimelineExercise(
        id: 'slides',
        name: 'Slides',
        description: 'Pitch slides build accuracy and vocal flexibility.',
        level: 1,
        minutes: 5,
        completed: true,
      ),
      TimelineExercise(
        id: 'breathing',
        name: 'Breathing',
        description: 'Proper breathing is the foundation of good vocal technique.',
        level: 1,
        minutes: 10,
        completed: false, // Next
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
    _selectedExerciseId = null;
  }

  TimelineExercise? _getNextExercise() {
    for (final exercise in _orderedExercises) {
      if (!exercise.completed) return exercise;
    }
    return _orderedExercises.last;
  }

  TimelineExercise? _getSelectedExercise() {
    if (_selectedExerciseId == null) return null;
    try {
      return _exercises.firstWhere((e) => e.id == _selectedExerciseId);
    } catch (e) {
      return _getNextExercise();
    }
  }

  void _selectExercise(String exerciseId) {
    setState(() {
      if (_selectedExerciseId != null) {
        _lastSelectedExercise = _getSelectedExercise();
      }
      if (_selectedExerciseId == exerciseId) {
        _selectedExerciseId = null;
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted && _selectedExerciseId == null) {
            setState(() {
              _lastSelectedExercise = null;
            });
          }
        });
      } else {
        _selectedExerciseId = exerciseId;
        _lastSelectedExercise = null;
      }
    });
  }

  List<TimelineExercise> get _orderedExercises => [
        _exercises[0],
        _exercises[1],
        _exercises[2],
        _exercises[3],
        _exercises[4],
      ];

  Future<void> _startExercise(TimelineExercise exercise) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExercisePreviewScreen(exerciseId: exercise.id),
      ),
    );

    if (mounted && result != null) {
      final index = _exercises.indexWhere((e) => e.id == exercise.id);
      if (index != -1) {
        setState(() {
          _exercises[index] = _exercises[index].copyWith(completed: true);
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

    // Adjusted anchors for Ballad layout
    final goldTop = safeAreaTop + 84;
    final goldHeight = 0.52 * H;
    final goldBottom = goldTop + goldHeight;

    final n4 = Offset(0.40 * W, goldTop + 0.14 * goldHeight);
    final n3 = Offset(0.30 * W, goldTop + 0.30 * goldHeight);
    final n2 = Offset(0.24 * W, goldTop + 0.48 * goldHeight);
    final play = Offset(0.34 * W, goldTop + 0.73 * goldHeight);
    final take = Offset(0.57 * W, goldBottom + 0.02 * H);

    const smallR = 30.0;
    const nextR = 50.0;
    const takeR = 54.0;

    final nextExercise = _getNextExercise();
    final selectedExercise = _getSelectedExercise() ?? nextExercise ?? _orderedExercises.first;

    return BalladScaffold(
      title: 'Your Journey',
      padding: EdgeInsets.zero, // Use full screen for absolute positioning
      child: Stack(
        children: [
          // Background Elements? 
          // BalladScaffold provides the main gradient.
          
          // Exercise info overlay
          Positioned(
            right: (screenWidth - (take.dx + takeR + 100)) / 2,
            top: H * 0.30,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 800),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
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

          // Timeline Arc and Nodes
          GestureDetector(
            onTap: () {
              if (_selectedExerciseId != null) {
                setState(() => _selectedExerciseId = null);
              }
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TimelineSplinePainter(
                      points: [n4, n3, n2, play, take],
                    ),
                  ),
                ),

                // Nodes
                _buildNodePositioned(n4, smallR, _orderedExercises[0], Colors.white.withOpacity(0.3)),
                _buildNodePositioned(n3, smallR, _orderedExercises[1], Colors.white.withOpacity(0.5)),
                _buildNodePositioned(n2, smallR, _orderedExercises[2], Colors.white.withOpacity(0.7)),
                
                // Next Exercise (Play)
                Positioned(
                  left: play.dx - nextR,
                  top: play.dy - nextR,
                  child: GestureDetector(
                    onTap: () => _handleTap(_orderedExercises[3]),
                    child: AnimatedScale(
                      scale: _selectedExerciseId == _orderedExercises[3].id ? 1.15 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        width: nextR * 2,
                        height: nextR * 2,
                        decoration: BoxDecoration(
                          gradient: BalladTheme.primaryButtonGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                             BoxShadow(
                              color: BalladTheme.accentTeal.withOpacity(0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: _selectedExerciseId == _orderedExercises[3].id
                              ? Icon(Icons.play_arrow, color: Colors.white, size: nextR * 0.8)
                              : Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    _orderedExercises[3].name,
                                    textAlign: TextAlign.center,
                                    style: BalladTheme.labelLarge.copyWith(fontSize: 14),
                                    maxLines: 2,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Take Exercise
                Positioned(
                  left: take.dx - takeR,
                  top: take.dy - takeR,
                  child: GestureDetector(
                    onTap: () => _handleTap(_orderedExercises[4]),
                    child: AnimatedScale(
                      scale: _selectedExerciseId == _orderedExercises[4].id ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        width: takeR * 2,
                        height: takeR * 2,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [BalladTheme.accentGold, Color(0xFFFFCC80)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: BalladTheme.accentGold.withOpacity(0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: _selectedExerciseId == _orderedExercises[4].id
                              ? Icon(Icons.play_arrow, color: Colors.white, size: takeR * 0.8)
                              : Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    _orderedExercises[4].name,
                                    textAlign: TextAlign.center,
                                    style: BalladTheme.labelLarge.copyWith(
                                      color: Colors.black87, // Gold bg needs dark text? or white?
                                      // Ballad buttons usually white text on gradient. 
                                      // But gold is light. Let's try dark text or keep it consistent.
                                      // BalladPrimaryButton uses white text on teal/purple.
                                      // Let's use darker text for contrast on gold.
                                      // actually lets use white text with shadow or just semi-bold.
                                      // Gold (FFD700) is bright. White text might be hard to read.
                                      // I'll stick to BalladTheme.textPrimary (white-ish) but maybe add shadow depending on contrast.
                                      // Ah, BalladTheme.accentGold is Color(0xFFFFD700).
                                      // Let's use dark text for Gold buttons.
                                      color: const Color(0xFF3E2D5C), // Dark purple/navy 
                                    ),
                                    maxLines: 2,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleTap(TimelineExercise exercise) {
    if (_selectedExerciseId == exercise.id) {
      _startExercise(exercise);
    } else {
      _selectExercise(exercise.id);
    }
  }

  Widget _buildNodePositioned(Offset pos, double radius, TimelineExercise exercise, Color color) {
    return Positioned(
      left: pos.dx - radius,
      top: pos.dy - radius,
      child: GestureDetector(
        onTap: () => _handleTap(exercise),
        child: AnimatedScale(
          scale: _selectedExerciseId == exercise.id ? 1.1 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: _TimelineExerciseNode(
            exercise: exercise,
            size: radius * 2,
            color: color,
            isSelected: _selectedExerciseId == exercise.id,
          ),
        ),
      ),
    );
  }
}

class _AppearingExerciseNames extends StatelessWidget {
  final TimelineExercise exercise;

  const _AppearingExerciseNames({
    required this.exercise,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey(exercise.id),
      width: 220,
      height: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              exercise.name,
              style: BalladTheme.titleLarge.copyWith(fontSize: 32),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${exercise.minutes} min',
            style: BalladTheme.bodyMedium.copyWith(
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            exercise.description,
            style: BalladTheme.bodyMedium.copyWith(fontSize: 12, color: Colors.white.withOpacity(0.5)),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _TimelineExerciseNode extends StatelessWidget {
  final TimelineExercise exercise;
  final double size;
  final Color color;
  final bool isSelected;

  const _TimelineExerciseNode({
    required this.exercise,
    required this.size,
    required this.color,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
        boxShadow: isSelected ? [
          BoxShadow(
            color: color.withOpacity(0.6),
            blurRadius: 12,
            spreadRadius: 2,
          )
        ] : null,
      ),
      child: Center(
        child: isSelected
            ? Icon(Icons.play_arrow, color: Colors.white, size: size * 0.4)
            : exercise.completed
                ? Icon(Icons.check, color: Colors.white, size: size * 0.4)
                : Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      exercise.name,
                      textAlign: TextAlign.center,
                      style: BalladTheme.labelSmall.copyWith(
                        fontSize: 10,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
      ),
    );
  }
}

class _TimelineSplinePainter extends CustomPainter {
  final List<Offset> points;

  _TimelineSplinePainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Draw splines between points
    // Simplified: Just draw nice curves or straight lines for now, 
    // or reimplement CatmullRom if I had the helper.
    // I will use a simple smooth path since I don't want to reimplement the complex helper right now if not needed,
    // but the original file had `_catmullRomToBezier`. I should ideally include it.
    
    // Re-implementing simplified curve
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    
    // Quadratic beziers between points
    for (int i = 0; i < points.length - 1; i++) {
        final p1 = points[i];
        final p2 = points[i+1];
        // Control point logic (midpoint with some offset?)
        // Let's just draw straight line or simple curve
        // Using QuadraticBezier to midpoint
        path.quadraticBezierTo(
            p1.dx, p2.dy, // Control point roughly forming an arc?
            p2.dx, p2.dy
        );
        // This might look jagged. 
        // Let's copy the helper logic from memory/previous file or just use standard smooth curve.
    }

    // Better: Draw a single arc?
    // The points are n4, n3, n2, play, take.
    // They roughly form a spiral/arc.
    // I'll stick to the original helper if I can, but I overwrote it.
    // Wait, I can reproduce the helper.
    
    _drawCatmullRom(canvas, paint, points);
  }

  void _drawCatmullRom(Canvas canvas, Paint paint, List<Offset> points) {
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 0; i < points.length - 1; i++) {
        final p0 = i > 0 ? points[i-1] : points[i];
        final p1 = points[i];
        final p2 = points[i+1];
        final p3 = i < points.length - 2 ? points[i+2] : points[i+1];
        
        // Catmull-Rom to Cubic Bezier conversion
        // p1 -> p2
        // cp1 = p1 + (p2 - p0) / 6 * tension (0.5)
        // cp2 = p2 - (p3 - p1) / 6 * tension
        
        const t = 0.5;
        final d1 = p2 - p0;
        final d2 = p3 - p1;
        
        final cp1 = p1 + d1 * (t / 6.0);
        final cp2 = p2 - d2 * (t / 6.0);
        
        path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
