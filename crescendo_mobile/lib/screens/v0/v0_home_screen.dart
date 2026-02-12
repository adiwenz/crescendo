import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/ballad_theme.dart';


// V1 Imports
import '../../models/exercise.dart';
import '../../services/daily_exercise_service.dart';
import '../../state/library_store.dart';
import '../../screens/explore/exercise_preview_screen.dart';
import '../../utils/navigation_trace.dart';

// ---------------------------------------------------------------------------
// Main Screen
// ---------------------------------------------------------------------------

class V0HomeScreen extends StatefulWidget {
  const V0HomeScreen({super.key});

  @override
  State<V0HomeScreen> createState() => _V0HomeScreenState();
}

class _V0HomeScreenState extends State<V0HomeScreen> {
  // --- State ---
  List<Exercise>? _dailyExercises;
  bool _isLoading = true;
  String? _selectedExerciseId;

  // --- Computeds ---

  Exercise? get _selectedExercise {
    if (_dailyExercises == null) return null;
    final index = _dailyExercises!.indexWhere((e) => e.id == _selectedExerciseId);
    return index != -1 ? _dailyExercises![index] : null;
  }

  Set<String> get _completedIds => libraryStore.completedExerciseIds;

  int get _remainingMinutes {
    if (_dailyExercises == null) return 0;
    return dailyExerciseService.calculateRemainingMinutes(_dailyExercises!, _completedIds);
  }

  double get _progress {
    if (_dailyExercises == null || _dailyExercises!.isEmpty) return 0.0;
    final total = dailyExerciseService.totalPlannedDurationSec(_dailyExercises!);
    final completed = dailyExerciseService.completedDurationSec(_dailyExercises!, _completedIds);
    if (total == 0) return 0.0;
    return (completed / total).clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    _loadDailyExercises();
    libraryStore.addListener(_onCompletionChanged);
  }

  @override
  void dispose() {
    libraryStore.removeListener(_onCompletionChanged);
    super.dispose();
  }

  void _onCompletionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadDailyExercises() async {
    final exercises = await dailyExerciseService.getTodaysExercises();
    if (mounted) {
      setState(() {
        _dailyExercises = exercises;
        _isLoading = false;
        
        // Auto-select first uncompleted if no selection
        if (_selectedExerciseId == null) {
            // Optionally auto-select? Let's stay neutral (null) or select next up.
            // User requirement: "No selection initially" (from previous code)
            // But usually nice to have one selected? I'll stick to null to match V0 existing behavior.
        }
      });
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

    // Navigate to V1 Preview Screen
    final trace = NavigationTrace.start('V0Home tap - pushing Navigator');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExercisePreviewScreen(
          exerciseId: _selectedExercise!.id,
          trace: trace,
        ),
      ),
    );
    
    // Completion is handled via libraryStore listener
    // But we might want to refresh simply to be safe
    _onCompletionChanged();
  }

  void _onBackgroundTap() {
    if (_selectedExerciseId != null) {
      setState(() {
        _selectedExerciseId = null;
      });
    }
  }

  Color _getColorForExercise(Exercise ex) {
    // Map bannerStyleId to BalladTheme colors
    switch (ex.bannerStyleId % 6) {
      case 0: return BalladTheme.accentBlue;
      case 1: return BalladTheme.accentPurple;
      case 2: return BalladTheme.accentTeal;
      case 3: return BalladTheme.accentPink;
      case 4: return BalladTheme.accentLavender;
      case 5: return BalladTheme.accentGold;
      default: return BalladTheme.accentBlue;
    }
  }

  // --- UI Components ---

  @override
  Widget build(BuildContext context) {
    // 2) Background Gradient
    // Lavender/Blue (top) -> Teal/Green (middle) -> Soft Aqua (bottom)
    // Using BalladTheme gradient would be consistent, but V0 had a specific look.
    // Let's us BalladTheme.backgroundGradient for consistency with the "Integration" goal.
    // Or keep V0's gradient as "Legacy UI". 
    // "Keep the V0 Home Screen UI/structure" -> I will keep V0 gradient for now to satisfy "Do not redesign V0 UI".
    
    final gradientColors = [
      const Color(0xFF0e2763), // Lavender/Blue
      const Color(0xFF80CBC4), // Teal/Green
      const Color(0xFFB2DFDB), // Soft Aqua
    ];

    return Scaffold(
      extendBodyBehindAppBar: true, 
      backgroundColor: Colors.white,
      body: GestureDetector(
        onTap: _onBackgroundTap,
        behavior: HitTestBehavior.translucent,
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
                  const SizedBox(height: 20),
                  Expanded(
                    child: _isLoading 
                      ? const Center(child: CircularProgressIndicator(color: Colors.white))
                      : Stack(
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
                            children: _dailyExercises!.asMap().entries.map((entry) {
                              final index = entry.key;
                              final exercise = entry.value;
                              
                              // Calculate horizontal offset for arc effect
                              // normalizedIndex: 0.0 -> 1.0 (Top -> Bottom)
                              final double normalizedIndex = index / (_dailyExercises!.length - 1);
                              
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
                  // Add bottom padding to account for BottomNavigationBar if needed, 
                  // but SafeArea usually handles system bottom. 
                  // App.dart wraps this in a Scaffold with BottomNavigationBar.
                  // The body height will effectively end above the nav bar.
                  // So we usually don't need extra padding unless we want visual space.
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
              border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.5),
            ),
            child: Icon(Icons.question_mark_rounded, color: Colors.white.withValues(alpha: 0.6), size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseCircleWidget(Exercise exercise, int number) {
    final isSelected = _selectedExerciseId == exercise.id;
    final isCompleted = _completedIds.contains(exercise.id);
    final color = _getColorForExercise(exercise);

    // Logic: Identify "Next Up" exercise
    final nextUpExercise = _dailyExercises!.firstWhere(
      (e) => !_completedIds.contains(e.id), 
      orElse: () => _dailyExercises!.last 
    );
    
    final bool isAllCompleted = _dailyExercises!.every((e) => _completedIds.contains(e.id));
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
              // Mostly flat gradient (Linear instead of Radial)
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(color, Colors.white, 0.2)!, // Subtle highlight
                  color,
                  Color.lerp(color, Colors.black, 0.1)!, // Subtle shadow
                ],
              ),
              boxShadow: [
                // 1) "Next Up" Bright White Glow
                if (isNextUp)
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.5), 
                    blurRadius: 16,
                    spreadRadius: 3,
                  ),

                 // 2) Standard Selection Glow 
                 if (isSelected && !isNextUp)
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.3),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),

                // 3) Softer Drop Shadow
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2), // Lighter/Softer shadow
                  blurRadius: isSelected ? 16 : 8,
                  spreadRadius: isSelected ? 2 : 0,
                  offset: isSelected ? Offset.zero : const Offset(2, 4), 
                )
              ],
            ),
          ),

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
                          color: Colors.white.withValues(alpha: 0.95),
                          size: 38,
                        ),
                      ),
                    )
                  : Center(
                      key: const ValueKey("number"),
                      child: isCompleted
                          ? Icon(Icons.check, color: Colors.white.withValues(alpha: 0.9), size: 28)
                          : Text(
                              "$number",
                              style: GoogleFonts.manrope(
                                fontSize: 22,
                                fontWeight: FontWeight.w700, // Bolder for clarity against gradients
                                color: Colors.white.withValues(alpha: 0.95),
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
    
    if (_dailyExercises == null) {
       return const SizedBox.shrink();
    }

    bool allDone = _dailyExercises!.every((e) => _completedIds.contains(e.id));
    
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
      description = _selectedExercise!.subtitle; // V1 model uses subtitle for description
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
            color: Colors.white.withValues(alpha: 0.08), // Very subtle glass
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.05),
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.4,
                  ),
                ),
                if (_selectedExercise != null) ...[
                   const SizedBox(height: 12),
                   Text(
                     "${(_selectedExercise!.estimatedDurationSec / 60).ceil()} min", // Show duration
                     style: GoogleFonts.manrope(
                       fontSize: 14,
                       fontWeight: FontWeight.w600,
                       color: Colors.white.withValues(alpha: 0.8),
                     ),
                   )
                ]
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomProgress() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      height: 120, // Taller area for spacious look
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
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
                          color: Colors.white.withValues(alpha: 0.8),
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
                          color: Colors.white.withValues(alpha: 0.4),
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
                            color: const Color(0xFF4DB6AC).withValues(alpha: 1),
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
                  color: Colors.white.withValues(alpha: 0.8),
                  blurRadius: widget.star.size * 2,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
