import 'dart:ui';
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
      color: const Color(0xFF81D4FA), // Light Blue
    ),
    Exercise(
      id: "2",
      title: "Breath Control",
      description: "Expand your lung capacity and control",
      durationMinutes: 7,
      color: const Color(0xFF9FA8DA), // Indigo/Periwinkle
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

  Exercise? get _selectedExercise => 
      _exercises.firstWhere((e) => e.id == _selectedExerciseId, orElse: () => _exercises.first);

  int get _totalMinutes => _exercises.fold(0, (sum, e) => sum + e.durationMinutes);
  
  int get _completedMinutes => _exercises
      .where((e) => e.isCompleted)
      .fold(0, (sum, e) => sum + e.durationMinutes);
      
  double get _progress => _totalMinutes == 0 ? 0 : _completedMinutes / _totalMinutes;
  
  int get _remainingMinutes => _totalMinutes - _completedMinutes;

  @override
  void initState() {
    super.initState();
    // Default selection
    if (_exercises.isNotEmpty) {
      _selectedExerciseId = _exercises.first.id;
    }
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

  // --- UI Components ---

  @override
  Widget build(BuildContext context) {
    // 2) Background Gradient
    // Lavender/Blue (top) -> Teal/Green (middle) -> Soft Aqua (bottom)
    // Approximate colors based on description/screenshot
    final gradientColors = [
      const Color(0xFFC5CAE9), // Lavender/Blue
      const Color(0xFF80CBC4), // Teal/Green
      const Color(0xFFB2DFDB), // Soft Aqua
    ];

    return Scaffold(
      extendBodyBehindAppBar: true, 
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: gradientColors,
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          
          // Subtle texture/grain could go here (omitted for pure Flutter implementation without assets)

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1) Header
                _buildHeader(),
                
                Expanded(
                  child: Stack(
                    children: [
                      // 3) Left Side Vertical Circles
                      Positioned(
                        top: 40,
                        bottom: 100,
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
                            
                            // Parabolic approximation of sine wave for 0 -> 1 -> 0
                            // y = 4 * x * (1 - x)
                            final double parabola = 4 * normalizedIndex * (1.0 - normalizedIndex);
                            final double xTranslation = curveAmplitude * parabola;

                            return Transform.translate(
                              offset: Offset(xTranslation, 0),
                              child: _buildExerciseCircle(exercise),
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
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Hamburger Icon
          Icon(Icons.menu, color: Colors.white.withOpacity(0.6), size: 28),
          
          // Title
          Text(
            "Today's Exercises",
            style: GoogleFonts.manrope(
              fontSize: 22,
              fontWeight: FontWeight.w300, // Thin/Light
              color: Colors.white,
              letterSpacing: 0.5,
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

  Widget _buildExerciseCircle(Exercise exercise) {
    final isSelected = _selectedExerciseId == exercise.id;
    final isCompleted = exercise.isCompleted;

    // Dimensions
    final double size = isSelected ? 72 : 56;
    
    return GestureDetector(
      onTap: () => _onCircleTap(exercise),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isCompleted 
              ? exercise.color.withOpacity(0.3) // Desaturated/dimmed
              : exercise.color.withOpacity(0.8),
          boxShadow: isSelected && !isCompleted
              ? [
                  BoxShadow(
                    color: exercise.color.withOpacity(0.6),
                    blurRadius: 20,
                    spreadRadius: 2,
                  )
                ]
              : [],
        ),
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
                      color: Colors.white.withOpacity(0.9),
                      size: 32,
                    ),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey("empty")), // Plain circle
        ),
      ),
    );
  }

  Widget _buildInfoContent() {
    if (_selectedExercise == null) return const SizedBox.shrink();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(animation),
          child: child,
        ));
      },
      child: Column(
        key: ValueKey(_selectedExercise!.id), // Key changes triggers animation
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _selectedExercise!.title,
            style: GoogleFonts.manrope(
              fontSize: 32,
              fontWeight: FontWeight.w400,
              color: Colors.white,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _selectedExercise!.description,
            style: GoogleFonts.manrope(
              fontSize: 18,
              fontWeight: FontWeight.w300,
              color: Colors.white.withOpacity(0.9),
              height: 1.4,
            ),
          ),
        ],
      ),
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
            // Frosted Glass Effect
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: Colors.white.withOpacity(0.2), // Translucent white
              ),
            ),
            
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
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        "~$_remainingMinutes min left",
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                          color: Colors.white.withOpacity(0.7),
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
                          color: Colors.white.withOpacity(0.2),
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
                            color: const Color(0xFF4DB6AC).withOpacity(0.8),
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
