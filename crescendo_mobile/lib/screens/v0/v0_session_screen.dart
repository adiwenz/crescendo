import 'package:flutter/material.dart';
import '../../services/exercise_repository.dart';
import '../../models/vocal_exercise.dart';
import '../../models/pitch_highway_difficulty.dart';
import '../../ui/screens/pitch_highway_screen.dart';
import '../../ui/screens/exercise_player_screen.dart';
import '../../widgets/ballad_scaffold.dart';
import '../../theme/ballad_theme.dart';
import 'v0_complete_screen.dart';

class V0SessionScreen extends StatefulWidget {
  const V0SessionScreen({super.key});

  @override
  State<V0SessionScreen> createState() => _V0SessionScreenState();
}

class _V0SessionScreenState extends State<V0SessionScreen> {
  // Define the ordered list of exercises for V0
  // 1) Match the Note -> sustained_pitch_holds
  // 2) Follow the Notes -> five_tone_scales
  // 3) Easy Slides -> ng_slides
  final List<String> _exerciseIds = [
    'sustained_pitch_holds',
    'five_tone_scales',
    'ng_slides',
  ];

  int _currentIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Start the first exercise immediately after the build phase
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _processNextStep();
    });
  }

  Future<void> _processNextStep() async {
    if (_currentIndex >= _exerciseIds.length) {
      _finishSession();
      return;
    }

    setState(() => _isLoading = true);

    final exerciseId = _exerciseIds[_currentIndex];
    await _launchExercise(exerciseId);

    // When exercise finishes (pops), move to next
    if (mounted) {
       setState(() {
         _currentIndex++;
         // Keep loading true as we loop immediately
       });
       // Auto-start next
       _processNextStep();
    }
  }
  
  Future<void> _launchExercise(String exerciseId) async {
    final repo = ExerciseRepository.instance;
    try {
      final exercise = repo.getExercise(exerciseId);

      if (exercise.type == ExerciseType.pitchHighway) {
         // V0 uses generic difficulty or hardcoded specific behavior
         // Assuming beginner/easy difficulty for V0
         await Navigator.of(context).push(
           MaterialPageRoute(
             builder: (_) => PitchHighwayScreen(
               exercise: exercise,
               pitchDifficulty: PitchHighwayDifficulty.easy, 
             ),
           ),
         );
      } else {
         // Standard exercise player
         await Navigator.of(context).push(
           MaterialPageRoute(
             builder: (_) => ExercisePlayerScreen(
               exercise: exercise,
             ),
           ),
         );
      }
    } catch (e) {
      debugPrint("V0 Error: Could not launch exercise $exerciseId: $e");
      // Skip if error (maybe show toast in a real app)
    }
  }

  void _finishSession() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const V0CompleteScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show loading while transitioning between exercises
    // Show loading while transitioning between exercises
    return const BalladScaffold(
      title: "Session in Progress",
      showBack: false,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              "Loading next exercise...",
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
