import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// 1. Data Model
// ---------------------------------------------------------------------------

class Exercise {
  final String id;
  final String title;
  final String description;
  final int durationMinutes;
  bool isCompleted;
  
  // Visual properties for the "balls"
  final Color color;

  Exercise({
    required this.id,
    required this.title,
    required this.description,
    required this.durationMinutes,
    this.isCompleted = false,
    required this.color,
  });
}

// ---------------------------------------------------------------------------
// 2. Exercise Preview Page (Placeholder)
// ---------------------------------------------------------------------------

class ExercisePreviewPage extends StatelessWidget {
  final Exercise exercise;

  const ExercisePreviewPage({super.key, required this.exercise});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(exercise.title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Previewing: ${exercise.title}", style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Determine completion logic here if needed, or just pop
                Navigator.of(context).pop(true); // Return true to simulate completion
              },
              child: const Text("Complete Exercise (Simulate)"),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Main Screen
// ---------------------------------------------------------------------------

class V0HomeScreen extends StatefulWidget {
  const V0HomeScreen({super.key});

  @override
  State<V0HomeScreen> createState() => _V0HomeScreenState();
}

class _V0HomeScreenState extends State<V0HomeScreen> {
  // --- State ---
  
  // Sample Data
  final List<Exercise> _exercises = [
    Exercise(
      id: "1",
      title: "Warm Up",
      description: "Gently get your voice ready to sing",
      durationMinutes: 5,
      color: const Color(0xFF0394FC), // Light Blue
    ),
    Exercise(
      id: "2",
      title: "Breath Control",
      description: "Expand your lung capacity and control",
      durationMinutes: 7,
      color: const Color(0xFF8403fc), // Indigo/Periwinkle
    ),
    Exercise(
      id: "3",
      title: "Pitch Perfect",
      description: "Train your ear to match frequencies",
      durationMinutes: 6,
      color: const Color(0xFFB39DDB), // Deep Purple
    ),
    Exercise(
      id: "4",
      title: "Agility",
      description: "Fast-paced runs and melisma",
      durationMinutes: 8,
      color: const Color(0xFFCE93D8), // Purple/Pink
    ),
    Exercise(
      id: "5",
      title: "Cool Down",
      description: "Relax your cords after training",
      durationMinutes: 4,
      color: const Color(0xFFF48FB1), // Pink
    ),
  ];

  String? _selectedExerciseId;

  // --- Computed Properties ---

  Exercise? get _selectedExercise {
    final index = _exercises.indexWhere((e) => e.id == _selectedExerciseId);
    return index != -1 ? _exercises[index] : null;
  }

  int get _totalMinutes => _exercises.fold(0, (sum, e) => sum + e.durationMinutes);
  
  int get _completedMinutes => _exercises
      .where((e) => e.isCompleted)
      .fold(0, (sum, e) => sum + e.durationMinutes);
      
  double get _progress => _totalMinutes == 0 ? 0 : _completedMinutes / _totalMinutes;
  
  int get _remainingMinutes => _totalMinutes - _completedMinutes;

  @override
  void initState() {
    super.initState();
    // Default selection is now NULL (No selection initially)
  }
  
  // --- Actions ---

  void _onCircleTap(Exercise exercise) {
    setState(() {
      _selectedExerciseId = exercise.id;
    });
  }

  void _onPlayTap() async {
    if (_selectedExercise == null) return;
    
    // Haptic feedback
    HapticFeedback.lightImpact();

    // Navigate
    final bool? completed = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ExercisePreviewPage(exercise: _selectedExercise!))
    );

    // TODO: Hook up real completion events here.
    // For now, if the preview page returns true, mark as complete.
    if (completed == true) {
      setState(() {
        _selectedExercise!.isCompleted = true;
      });
    }
  }

  void _onBackgroundTap() {
    if (_selectedExerciseId != null) {
      setState(() {
        _selectedExerciseId = null;
      });
    }
  }

  // --- UI Components ---

  @override
  Widget build(BuildContext context) {
    // 2) Background Gradient
    // Lavender/Blue (top) -> Teal/Green (middle) -> Soft Aqua (bottom)
    // Approximate colors based on description/screenshot
    final gradientColors = [
      // const Color(0xFFC5CAE9), // Lavender/Blue
      const Color(0xFF0e2763), // Lavender/Blue
      const Color(0xFF80CBC4), // Teal/Green
      const Color(0xFFB2DFDB), // Soft Aqua
    ];

    return Scaffold(
      extendBodyBehindAppBar: true, 
      backgroundColor: Colors.white,
      body: GestureDetector(
        onTap: _onBackgroundTap,
        behavior: HitTestBehavior.translucent, // Catch taps on empty space
        child: Stack(
          children: [
            // Background
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: gradientColors,
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
            ),
            
            // Subtle texture/grain could go here (omitted for pure Flutter implementation without assets)
            
            // Glow Stars Background
            const Positioned.fill(
              child: PulsatingStars(),
            ),
  
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1) Header
                  _buildHeaderWidget(),
                  SizedBox(height: 20),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 3) Left Side Vertical Circles
                        Positioned(
                          top: 0,
                          bottom: 0,
                          left: 20,
                          width: 100, // Constrain width of the ball column
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: _exercises.asMap().entries.map((entry) {
                              final index = entry.key;
                              final exercise = entry.value;
                              
                              // Calculate horizontal offset for arc effect
                              // normalizedIndex: 0.0 -> 1.0 (Top -> Bottom)
                              final double normalizedIndex = index / (_exercises.length - 1);
                              
                              // Amplitude: How far right the arc goes (approx 8% of screen width ~ 35px)
                              const double curveAmplitude = 35.0; 
                              
                              // Parabolic approximation of sine wave for 1 -> 0 -> 1 (Bulge Left, Open Right)
                              // y = 1.0 - (4 * x * (1 - x))
                              final double parabola = 4 * normalizedIndex * (1.0 - normalizedIndex);
                              final double xTranslation = curveAmplitude * (1.0 - parabola);
  
                              return Transform.translate(
                                offset: Offset(xTranslation, 0),
                                child: _buildExerciseCircleWidget(exercise, index + 1),
                              );
                            }).toList(),
                          ),
                        ),
  
                        // 4) Main Content Area (Right)
                        Positioned(
                          top: 0,
                          bottom: 0,
                          left: 140, // To right of balls
                          right: 20,
                          child: Center(
                            child: _buildInfoContent(),
                          ),
                        ),
                      ],
                    ),
                  ),
  
                  // 5) Bottom Progress Section
                  _buildBottomProgress(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Helper Methods ---

  Widget _buildHeaderWidget() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Title
          const SizedBox(width: 20),
          Text(
            "Ballad",
            style: GoogleFonts.dmSerifDisplay(
              fontSize: 60,
              fontWeight: FontWeight.w400, // Thin/Light
              color: Colors.white,
              letterSpacing: 0.5,
              // textAlign: TextAlign.center,
            ),
          ),
          
          // Help Icon
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
            ),
            child: Icon(Icons.question_mark_rounded, color: Colors.white.withOpacity(0.6), size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseCircleWidget(Exercise exercise, int number) {
    final isSelected = _selectedExerciseId == exercise.id;
    final isCompleted = exercise.isCompleted;

    // Logic: Identify "Next Up" exercise
    final nextUpExercise = _exercises.firstWhere(
      (e) => !e.isCompleted, 
      orElse: () => _exercises.last 
    );
    
    final bool isAllCompleted = _exercises.every((e) => e.isCompleted);
    final bool isNextUp = !isAllCompleted && (exercise.id == nextUpExercise.id);

    // Dimensions
    final double size = isSelected ? 84 : 64;
    
    return GestureDetector(
      onTap: () => _onCircleTap(exercise),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Base Sphere & Shadow
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Enhanced 3D Gradient (Radial) - Base
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.3), // Light source top-left
                radius: 1.3,
                colors: [
                  // Highlight (Top Left) -> Body -> Shadow (Bottom Right)
                  Color.lerp(exercise.color, Colors.white, 0.4)!, // Lighter highlight
                  exercise.color, // Main Body
                  Color.lerp(exercise.color, Colors.black, 0.6)!, // Deep Shadow
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
              boxShadow: [
                // 1) "Next Up" Bright White Glow
                if (isNextUp)
                  BoxShadow(
                    color: Colors.white.withOpacity(0.6), // Brighter/Stronger
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),

                 // 2) Standard Selection Glow 
                 if (isSelected && !isNextUp)
                  BoxShadow(
                    color: Colors.white.withOpacity(0.3),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),

                // 3) Deep Drop Shadow (Environment Shadow)
                BoxShadow(
                  color: Colors.black.withOpacity(0.4), // Darker shadow
                  blurRadius: isSelected ? 25 : 12,
                  spreadRadius: isSelected ? 4 : 0,
                  offset: isSelected ? Offset.zero : const Offset(4, 6), // Deep offset
                )
              ],
            ),
          ),

          // 2. Inner Glow / Reflected Light (Bottom Right)
          // Simulates light passing through or reflecting off the bottom inside
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(0.6, 0.6), // Bottom Right
                radius: 1.0,
                colors: [
                  Colors.white.withOpacity(0.2), // Subtle light
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5],
              ),
            ),
          ),

          // 3. Specular Highlight (Glossy Shine - Top Left)
          // Removed per user request
          // Positioned(
          //   top: size * 0.15,
          //   left: size * 0.15,
          //   child: Container( ... ),
          // ),

          // 4. Content (Icon/Number)
          SizedBox( // Ensure content is centered and constrained
            width: size,
            height: size,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isSelected
                  ? GestureDetector(
                      onTap: _onPlayTap, // Tap again to play
                      child: Container(
                        key: const ValueKey("play"),
                        decoration: const BoxDecoration(
                          color: Colors.transparent, 
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white.withOpacity(0.95),
                          size: 38,
                        ),
                      ),
                    )
                  : Center(
                      key: const ValueKey("number"),
                      child: Text(
                        "$number",
                        style: GoogleFonts.manrope(
                          fontSize: 22,
                          fontWeight: FontWeight.w700, // Bolder for clarity against gradients
                          color: Colors.white.withOpacity(0.95),
                          shadows: [
                            const Shadow(color: Colors.black45, offset: Offset(1,1), blurRadius: 3),
                          ]
                        ),
                      ),
                    ), 
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildInfoContent() {
    // Logic for content state
    String title;
    String description;
    Key key;
    
    bool allDone = _exercises.every((e) => e.isCompleted);
    
    if (allDone) {
      title = "Congrats!";
      description = "You finished your exercises for today";
      key = const ValueKey("congrats");
    } else if (_selectedExercise == null) {
      title = "Ready?";
      description = "Select an exercise to begin";
      key = const ValueKey("noselection");
    } else {
      title = _selectedExercise!.title;
      description = _selectedExercise!.description;
      key = ValueKey(_selectedExercise!.id);
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        // Glass Circle Background
        Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.08), // Very subtle glass
            boxShadow: [
              BoxShadow(
                color: Colors.white.withOpacity(0.05),
                blurRadius: 30,
                spreadRadius: 10,
              ),
            ],
          ),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),
        ),

        // Text Content
        Padding(
          padding: const EdgeInsets.all(32.0),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) {
              return FadeTransition(opacity: animation, child: ScaleTransition(
                scale: Tween<double>(begin: 0.95, end: 1.0).animate(animation),
                child: child,
              ));
            },
            child: Column(
              key: key, // Key changes triggers animation
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center, // Center align for glass circle
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 28, // Slightly smaller to fit circle
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                    color: Colors.white.withOpacity(0.9),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomProgress() {
    return Container(
      margin: const EdgeInsets.all(20),
      height: 120, // Taller area for spacious look
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // // Frosted Glass Effect
            // BackdropFilter(
            //   filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            //   child: Container(
            //     color: Colors.white.withOpacity(0.3), // Translucent white
            //   ),
            // ),
            
            // Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Progress",
                        style: GoogleFonts.manrope(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        "~$_remainingMinutes min left",
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Progress Bar
                  Stack(
                    children: [
                      // Background Track
                      Container(
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      // Fill
                      AnimatedFractionallySizedBox(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutCubic,
                        widthFactor: _progress,
                        child: Container(
                          height: 24,
                          decoration: BoxDecoration(
                            // Soft pastel fill (Teal/Blue ish)
                            color: const Color(0xFF4DB6AC).withOpacity(1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Helper widget for animated fractional sizing
class AnimatedFractionallySizedBox extends ImplicitlyAnimatedWidget {
  final double widthFactor;
  final Widget child;

  const AnimatedFractionallySizedBox({
    super.key,
    required this.widthFactor,
    required this.child,
    required super.duration,
    super.curve,
  });

  @override
  AnimatedWidgetBaseState<AnimatedFractionallySizedBox> createState() =>
      _AnimatedFractionallySizedBoxState();
}

class _AnimatedFractionallySizedBoxState
    extends AnimatedWidgetBaseState<AnimatedFractionallySizedBox> {
  Tween<double>? _widthFactorTween;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _widthFactorTween = visitor(
      _widthFactorTween,
      widget.widthFactor,
      (dynamic value) => Tween<double>(begin: value as double),
    ) as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: _widthFactorTween?.evaluate(animation),
      child: widget.child,
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Background Effects
// ---------------------------------------------------------------------------

class PulsatingStars extends StatelessWidget {
  const PulsatingStars({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PulsatingStarsImpl();
  }
}

class _PulsatingStarsImpl extends StatefulWidget {
  const _PulsatingStarsImpl();

  @override
  State<_PulsatingStarsImpl> createState() => _PulsatingStarsImplState();
}

class _PulsatingStarsImplState extends State<_PulsatingStarsImpl> {
  final List<_StarData> _stars = [];

  @override
  void initState() {
    super.initState();
    final random = math.Random();
    // Generate ~25 stars in the top 35% of the screen
    for (int i = 0; i < 25; i++) {
      _stars.add(_StarData(
        left: random.nextDouble(), // 0.0 - 1.0
        top: random.nextDouble() * 0.35, // Top 35%
        size: 2.0 + random.nextDouble() * 4.0, // 2-6px
        duration: Duration(milliseconds: 1500 + random.nextInt(2000)), // 1.5 - 3.5s
        initialProgress: random.nextDouble(), // Random start phase
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: _stars.map((star) {
            return Positioned(
              left: star.left * constraints.maxWidth,
              top: star.top * constraints.maxHeight,
              child: _PulsatingStar(
                key: ValueKey(star), // Ensure state preservation
                star: star,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _StarData {
  final double left;
  final double top;
  final double size;
  final Duration duration;
  final double initialProgress;

  _StarData({
    required this.left,
    required this.top,
    required this.size,
    required this.duration,
    required this.initialProgress,
  });
}

class _PulsatingStar extends StatefulWidget {
  final _StarData star;

  const _PulsatingStar({super.key, required this.star});

  @override
  State<_PulsatingStar> createState() => _PulsatingStarState();
}

class _PulsatingStarState extends State<_PulsatingStar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.star.duration,
      value: widget.star.initialProgress, // Start at random phase
    );

    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.2, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.2), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Container(
            width: widget.star.size,
            height: widget.star.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withOpacity(0.8),
                  blurRadius: 4,
                  spreadRadius: 1,
                )
              ],
            ),
          ),
        );
      },
    );
  }
}
