import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../controllers/pitch_matching_controller.dart';
import '../../models/vocal_exercise.dart';
import '../../services/audio_synth_service.dart';
import '../../services/recording_service.dart';
import '../theme/app_theme.dart';
import '../../models/reference_note.dart';

class PitchMatchingScreen extends StatefulWidget {
  final VocalExercise exercise;

  const PitchMatchingScreen({super.key, required this.exercise});

  @override
  State<PitchMatchingScreen> createState() => _PitchMatchingScreenState();
}

class _PitchMatchingScreenState extends State<PitchMatchingScreen>
    with SingleTickerProviderStateMixin {
  late PitchMatchingController _controller;
  final AudioSynthService _synth = AudioSynthService();
  final RecordingService _recording = RecordingService();
  StreamSubscription? _micSubscription;

  // Exercise State
  int _targetMidi = 60; // Default C4
  bool _isPlayingReference = false;
  
  // Animation for the ball
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = PitchMatchingController();
    _controller.setTargetMidi(_targetMidi.toDouble());
    
    // Setup pulse animation for matched state
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Initial setup
    _startCallAndResponseParams();
  }

  void _startCallAndResponseParams() {
      // In a real app we might randomise this or get from config
      setState(() {
          _targetMidi = 60 + math.Random().nextInt(12); // Random note within octave
          _controller.setTargetMidi(_targetMidi.toDouble());
      });
      // Auto-play reference
      _playReference();
  }

  Future<void> _playReference() async {
    if (_isPlayingReference) return;
    setState(() => _isPlayingReference = true);
    _controller.state.value = PitchMatchState.playingReference;
    
    final note = ReferenceNote(
        startSec: 0, 
        endSec: 1.5, 
        midi: _targetMidi
    );
    final file = await _synth.renderReferenceNotes([note]);
    await _synth.playFile(file);
    
    if (mounted) {
      setState(() => _isPlayingReference = false);
      _startListening();
    }
  }

  Future<void> _startListening() async {
    if (_micSubscription != null) return;
    
    _controller.startSession();
    await _recording.start(owner: 'PitchMatching');
    
    _micSubscription = _recording.liveStream.listen((frame) {
      _controller.processPitchFrame(frame);
    });
  }

  Future<void> _stopListening() async {
    _micSubscription?.cancel();
    _micSubscription = null;
    await _recording.stop();
  }

  void _onNext() {
      // Transition animation?
      _stopListening();
      _startCallAndResponseParams();
  }

  @override
  void dispose() {
    _micSubscription?.cancel();
    _recording.stop();
    _controller.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Theme colors
    final colors = AppThemeColors.of(context);
    final accentColor = colors.lavenderGlow; 
    final surfaceColor = colors.surface0;
    
    return Scaffold(
      backgroundColor: surfaceColor,
      appBar: AppBar(
        title: Text(widget.exercise.name),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Status / Instruction
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: ValueListenableBuilder<PitchMatchState>(
                  valueListenable: _controller.state,
                  builder: (context, state, _) {
                      String text;
                      switch(state) {
                          case PitchMatchState.playingReference: text = "Listen..."; break;
                          case PitchMatchState.listening: text = "Sing the Note"; break;
                          case PitchMatchState.singing: text = "Sing the Note"; break;
                          case PitchMatchState.matched: text = "Perfect!"; break;
                          default: text = "";
                      }
                      return Text(
                          text, 
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary
                          )
                      );
                  }
              ),
            ),
            
            // Main Visualization Area
            Expanded(
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Target Line (Static)
                    Container(
                      width: 200,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    
                    // Target Glow (when matched)
                    ValueListenableBuilder<bool>(
                        valueListenable: _controller.isSnapped,
                        builder: (context, snapped, child) {
                            if (!snapped) return const SizedBox.shrink();
                            return AnimatedBuilder(
                                animation: _pulseAnimation,
                                builder: (context, child) {
                                    return Container(
                                        width: 200,
                                        height: 40 * _pulseAnimation.value,
                                        decoration: BoxDecoration(
                                            color: accentColor.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(20),
                                            boxShadow: [
                                                BoxShadow(
                                                    color: accentColor.withOpacity(0.3),
                                                    blurRadius: 20,
                                                    spreadRadius: 5
                                                )
                                            ]
                                        ),
                                    );
                                }
                            );
                        }
                    ),

                    // Pitch Ball (Dynamic)
                    ValueListenableBuilder<double?>(
                      valueListenable: _controller.centsError,
                      builder: (context, cents, _) {
                          return ValueListenableBuilder<bool>(
                              valueListenable: _controller.isSnapped,
                              builder: (context, snapped, _) {
                                  // Determine ball position
                                  // Range of view: +/- 50 cents? 
                                  // Let's say +/- 50 cents maps to +/- 150 pixels
                                  final double rangeCents = 60.0; // visible range
                                  final double maxPixels = 150.0;
                                  
                                  double dy = 0;
                                  bool isVisible = false;
                                  
                                  if (snapped) {
                                      dy = 0;
                                      isVisible = true;
                                  } else if (cents != null) {
                                      // Clamp visual movement
                                      double visualCents = cents.clamp(-rangeCents, rangeCents);
                                      // Map to pixels (negative cents = below = positive Y in Flutter Stack? 
                                      // Wait, usually high pitch is UP (negative Y))
                                      // So positive cents (sharp) -> Up -> Negative Y
                                      dy = -(visualCents / rangeCents) * maxPixels;
                                      isVisible = true;
                                  }

                                  return AnimatedOpacity(
                                      duration: const Duration(milliseconds: 200),
                                      opacity: isVisible ? 1.0 : 0.2, // Ghost when silence
                                      child: AnimatedTranslation(
                                          offset: Offset(0, dy),
                                          duration: const Duration(milliseconds: 100), // Smooth lerp
                                          child: Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                  color: snapped ? accentColor : Colors.grey.shade400,
                                                  shape: BoxShape.circle,
                                                  boxShadow: snapped ? [
                                                      BoxShadow(
                                                          color: accentColor.withOpacity(0.5),
                                                          blurRadius: 12,
                                                          spreadRadius: 2
                                                      )
                                                  ] : [],
                                              ),
                                              child: Center(
                                                  child: Container(
                                                      width: 12,
                                                      height: 12,
                                                      decoration: const BoxDecoration(
                                                          color: Colors.white,
                                                          shape: BoxShape.circle,
                                                      ),
                                                  ),
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
              ),
            ),
            
            // Bottom Controls
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                      // Replay
                      FloatingActionButton(
                          heroTag: 'replay',
                          backgroundColor: Colors.white,
                          elevation: 2,
                          onPressed: _playReference,
                          child: const Icon(Icons.refresh, color: Colors.black87),
                      ),
                      
                      // Next / Success indicator
                      ValueListenableBuilder<bool>(
                          valueListenable: _controller.isSnapped,
                          builder: (context, snapped, _) {
                              return FloatingActionButton.extended(
                                  heroTag: 'next',
                                  backgroundColor: snapped ? accentColor : Colors.grey.shade300,
                                  elevation: snapped ? 4 : 0,
                                  label: Text("Next Note", 
                                      style: TextStyle(
                                          color: snapped ? Colors.white : Colors.grey.shade600
                                      )
                                  ),
                                  icon: Icon(Icons.arrow_forward, 
                                      color: snapped ? Colors.white : Colors.grey.shade600
                                  ),
                                  onPressed: snapped ? _onNext : null, // Or allow skip?
                              );
                          }
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

// Helper for smooth movement
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
