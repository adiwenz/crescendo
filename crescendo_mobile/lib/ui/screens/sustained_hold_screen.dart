import 'dart:async';
import 'package:flutter/material.dart';
import '../../controllers/sustained_hold_controller.dart';
import '../../models/vocal_exercise.dart';
import '../../services/audio_synth_service.dart';
import '../../services/recording_service.dart';
import '../theme/app_theme.dart';
import '../../models/reference_note.dart';
import '../../utils/pitch_math.dart';
import '../widgets/pitch_contour_card.dart';

class SustainedHoldScreen extends StatefulWidget {
  final VocalExercise exercise;

  const SustainedHoldScreen({super.key, required this.exercise});

  @override
  State<SustainedHoldScreen> createState() => _SustainedHoldScreenState();
}

class _SustainedHoldScreenState extends State<SustainedHoldScreen> {
  late SustainedHoldController _controller;
  final AudioSynthService _synth = AudioSynthService();
  final RecordingService _recording = RecordingService();
  StreamSubscription? _micSubscription;

  
  
  // Timer for duration updates
  Timer? _durationTimer;

  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _controller = SustainedHoldController();
    
    // Generate 5 notes starting from C4 (or exercise default)
    // Ideally we use user's range, but for now simple C Major ascent
    _controller.init([60, 62, 64, 65, 67]);

    // Start first note
    
    // Start first note
    _startNote();
  }

  Future<void> _startNote() async {
      await _synth.stop();
      if (_isDisposed) return;

      // Play continuous reference tone for ~5s
      final targetMidi = _controller.targetMidi;
      final note = ReferenceNote(
          startSec: 0, 
          endSec: SustainedHoldController.noteDurationSec, 
          midi: targetMidi.toInt()
      );
      final file = await _synth.renderReferenceNotes([note]);
      
      if (_isDisposed) return;
      await _synth.playFile(file);
      
      _controller.startNote();
      _startListening();
      
      // Start timer to update controller timeRemaining
      _durationTimer?.cancel();
      _durationTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
          if (_isDisposed) {
              timer.cancel();
              return;
          }
          _controller.updateTime(0.05);
          
          
          if (_controller.state.value == SustainedHoldState.feedback) {
              timer.cancel();
              _finishSet(); 
          } else if (_controller.state.value == SustainedHoldState.review) {
              timer.cancel();
              _finishSet();
          }
      });
  }

  Future<void> _startListening() async {
    if (_micSubscription != null) return;
    await _recording.start(owner: 'SustainedHold');
    _micSubscription = _recording.liveStream.listen((frame) {
      _controller.processPitchFrame(frame);
    });
  }

  Future<void> _stopListening() async {
    _micSubscription?.cancel();
    _micSubscription = null;
    await _recording.stop();
  }
  
  Future<void> _finishSet() async {
      _stopListening();
      _synth.stop();
      // Calculate overall score?
      // Use average stability
      
      // Save Attempt
      // ... implementation ...
  }
  
  void _repeatNote() {
      _controller.repeatNote();
      _startNote();
  }
  
  void _nextNote() {
      _controller.nextNote();
      if (_controller.state.value != SustainedHoldState.review) {
          _startNote();
      }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _micSubscription?.cancel();
    _recording.stop();
    _synth.stop();
    _controller.dispose();
    _durationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    
    return Container(
      color: colors.surface0,
      child: SafeArea(
        child: ValueListenableBuilder<SustainedHoldState>(
            valueListenable: _controller.state,
            builder: (context, state, _) {
                if (state == SustainedHoldState.review) {
                    return _buildReviewScreen(context);
                } else if (state == SustainedHoldState.feedback) {
                    return _buildFeedbackScreen(context);
                }
                return _buildExerciseScreen(context);
            }
        ),
      ),
    );
  }
  
  Widget _buildExerciseScreen(BuildContext context) {
      final colors = AppThemeColors.of(context);
      return Column(
          children: [
              // Header removed (provided by wrapper)
              const SizedBox(height: 16),
              
              // Progress Dots
              ValueListenableBuilder<int>(
                  valueListenable: _controller.currentNoteIndex,
                  builder: (context, index, _) {
                      return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(SustainedHoldController.notesInSet, (i) {
                               final active = i <= index;
                               return Container(
                                   margin: const EdgeInsets.symmetric(horizontal: 4),
                                   width: 8,
                                   height: 8,
                                   decoration: BoxDecoration(
                                       shape: BoxShape.circle,
                                       color: active ? colors.lavenderGlow : colors.iconMuted.withValues(alpha: 0.3)
                                   ),
                               );
                          }),
                      );
                  }
              ),
              
              const Spacer(),
              
              // Note Name
               ValueListenableBuilder<double>(
                  valueListenable: _controller.currentMidi,
                  builder: (context, _, __) {
                      final targetName = PitchMath.midiToName(_controller.targetMidi.toInt());
                      return Text(targetName, style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary
                      ));
                  }
              ),

              const SizedBox(height: 20),
              
              // Target Visual
              Stack(
                  alignment: Alignment.center,
                  children: [
                    // Target Line
                    Container(
                      width: 200,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    
                     // Pitch Ball
                    ValueListenableBuilder<double?>(
                      valueListenable: _controller.centsError,
                      builder: (context, cents, _) {
                          return ValueListenableBuilder<bool>(
                              valueListenable: _controller.isSnapped,
                              builder: (context, snapped, _) {

                                  double dy = 0;
                                  bool isVisible = false;
                                  const double rangeCents = 60.0; 
                                  const double maxPixels = 150.0;
                                  
                                  if (snapped) {
                                      dy = 0;
                                      isVisible = true;
                                  } else if (cents != null) {
                                      double visualCents = cents.clamp(-rangeCents, rangeCents);
                                      dy = -(visualCents / rangeCents) * maxPixels;
                                      isVisible = true;
                                  }

                                  return AnimatedOpacity(
                                      duration: const Duration(milliseconds: 200),
                                      opacity: isVisible ? 1.0 : 0.2,
                                      child: AnimatedTranslation( // Helper class
                                          offset: Offset(0, dy),
                                          duration: const Duration(milliseconds: 100),
                                          child: Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                  color: snapped ? colors.lavenderGlow : Colors.grey.shade400,
                                                  shape: BoxShape.circle,
                                                  boxShadow: snapped ? [
                                                      BoxShadow(
                                                          color: colors.lavenderGlow.withValues(alpha: 0.5),
                                                          blurRadius: 12,
                                                          spreadRadius: 2
                                                      )
                                                  ] : [],
                                              ),
                                          ),
                                      ),
                                  );
                              }
                          );
                      }
                    ),
                  ],
              ),
              
              const Spacer(),
              
              // Time / Stability
              ValueListenableBuilder<double>(
                  valueListenable: _controller.timeRemaining,
                  builder: (context, time, _) {
                      return Column(
                          children: [
                              Text("${time.toStringAsFixed(1)}s", style: TextStyle(
                                  fontSize: 24,
                                  color: colors.textSecondary
                              )),
                              const SizedBox(height: 8),
                              ValueListenableBuilder<double>(
                                  valueListenable: _controller.stabilityScore,
                                  builder: (context, score, _) {
                                      return Text("Stability: ${(score * 100).toInt()}%", style: TextStyle(
                                          color: colors.lavenderGlow,
                                          fontWeight: FontWeight.w600
                                      ));
                                  }
                              )
                          ],
                      );
                  }
              ),
              
              const SizedBox(height: 48),
          ],
      );
  }

  Widget _buildFeedbackScreen(BuildContext context) {
      final colors = AppThemeColors.of(context);
      final result = _controller.lastResult;
      
      return Center(
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                       Text("Note Complete", style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary
                      )),
                      const SizedBox(height: 24),
                      
                      if (result != null)
                          PitchContourCard(
                              targetMidi: result.targetMidi,
                              frames: result.frames,
                              height: 150,
                          ),
                          
                      const SizedBox(height: 48),
                      
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                              OutlinedButton(
                                  onPressed: _repeatNote,
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: colors.lavenderGlow,
                                      side: BorderSide(color: colors.lavenderGlow),
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)
                                  ),
                                  child: const Text("Repeat Note"),
                              ),
                              ElevatedButton(
                                  onPressed: _nextNote,
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: colors.lavenderGlow,
                                      foregroundColor: colors.surface0,
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)
                                  ),
                                  child: Text(_controller.currentNoteIndex.value == SustainedHoldController.notesInSet - 1 ? "Finish" : "Next Note"),
                              )
                          ],
                      )
                  ],
              ),
          ),
      );
  }

  Widget _buildReviewScreen(BuildContext context) {
       final colors = AppThemeColors.of(context);
       return Center(
           child: SingleChildScrollView(
             child: Padding(
               padding: const EdgeInsets.all(24.0),
               child: Column(
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                       Text("Set Complete!", style: TextStyle(
                           fontSize: 24, 
                           fontWeight: FontWeight.bold,
                           color: colors.textPrimary
                       )),
                       const SizedBox(height: 24),
                       // List of cards
                       ..._controller.results.map((r) => Padding(
                           padding: const EdgeInsets.only(bottom: 16.0),
                           child: Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                   Text("Note ${PitchMath.midiToName(r.targetMidi.toInt())}", 
                                       style: TextStyle(
                                           color: colors.textSecondary,
                                           fontWeight: FontWeight.w600
                                       )
                                   ),
                                   const SizedBox(height: 8),
                                   PitchContourCard(
                                       targetMidi: r.targetMidi,
                                       frames: r.frames,
                                       height: 80,
                                   ),
                               ],
                           ),
                       )),
                       const SizedBox(height: 32),
                       ElevatedButton(
                           onPressed: () => Navigator.of(context).pop(),
                           style: ElevatedButton.styleFrom(
                               backgroundColor: colors.lavenderGlow,
                               foregroundColor: colors.surface0,
                           ),
                           child: const Text("Done"),
                       )
                   ],
               ),
             ),
           ),
       );
  }
}

// Helper (duplicated from pitch_matching_screen for now)
class AnimatedTranslation extends StatelessWidget {
    final Offset offset;
    final Duration duration;
    final Widget child;

    const AnimatedTranslation({
        super.key,
        required this.offset,
        required this.duration,
        required this.child,
    });

    @override
    Widget build(BuildContext context) {
        return TweenAnimationBuilder<Offset>(
            tween: Tween<Offset>(begin: offset, end: offset),
            duration: duration,
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
                return Transform.translate(
                    offset: value,
                    child: child,
                );
            },
            child: child,
        );
    }
}
