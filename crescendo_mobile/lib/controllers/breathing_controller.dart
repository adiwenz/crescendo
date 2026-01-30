import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/breathing_phase.dart';

/// Controller for breathing animation and countdown logic
class BreathingController extends ChangeNotifier {
  final List<BreathingPhase> phases;
  final int repeatCount; // 0 = infinite, >0 = specific count
  final VoidCallback? onComplete;
  final TickerProvider vsync;

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  Timer? _countdownTimer;
  Timer? _preRollTimer;

  // State
  final ValueNotifier<int> countdown = ValueNotifier(0);
  final ValueNotifier<String> currentPhaseName = ValueNotifier('');
  final ValueNotifier<bool> isPreRoll = ValueNotifier(true);
  final ValueNotifier<int> currentCycle = ValueNotifier(0);

  int _currentPhaseIndex = 0;
  int _cyclesCompleted = 0;
  bool _isDisposed = false;
  double _pausedAnimationValue = 0.0;
  int _pausedCountdown = 0;

  BreathingController({
    required this.phases,
    required this.vsync,
    this.repeatCount = 1,
    this.onComplete,
  }) {
    _initializeController();
  }

  void _initializeController() {
    // Calculate total cycle duration
    final totalDuration = phases.fold<double>(
      0.0,
      (sum, phase) => sum + phase.durationSeconds,
    );

    _animationController = AnimationController(
      duration: Duration(milliseconds: (totalDuration * 1000).round()),
      vsync: vsync,
    );

    _buildScaleAnimation();
    _animationController.addListener(_onAnimationUpdate);
    _animationController.addStatusListener(_onAnimationStatus);
  }

  void _buildScaleAnimation() {
    // Build tween sequence based on phases
    final totalDuration = _animationController.duration!.inMilliseconds;
    double currentTime = 0.0;
    double currentScale = 1.0;

    final List<TweenSequenceItem<double>> items = [];

    for (int i = 0; i < phases.length; i++) {
      final phase = phases[i];
      final phaseDuration = phase.durationMs;
      final weight = phaseDuration / totalDuration;

      double targetScale;
      switch (phase.animationType) {
        case BreathingAnimationType.expand:
          targetScale = 1.5;
          break;
        case BreathingAnimationType.contract:
          targetScale = 1.0;
          break;
        case BreathingAnimationType.hold:
          targetScale = currentScale; // Maintain current scale
          break;
        case BreathingAnimationType.pulse:
          targetScale = currentScale * 1.05; // Subtle pulse
          break;
      }

      items.add(
        TweenSequenceItem(
          tween: Tween<double>(begin: currentScale, end: targetScale)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: weight,
        ),
      );

      currentScale = targetScale;
      currentTime += phaseDuration;
    }

    _scaleAnimation = TweenSequence<double>(items).animate(_animationController);
  }

  void _onAnimationUpdate() {
    if (_isDisposed) return;

    // Update current phase based on animation progress
    final elapsed = _animationController.value * _animationController.duration!.inMilliseconds;
    double cumulativeTime = 0.0;
    double phaseStartTime = 0.0;

    for (int i = 0; i < phases.length; i++) {
      cumulativeTime += phases[i].durationMs;
      if (elapsed < cumulativeTime) {
        if (_currentPhaseIndex != i) {
          _currentPhaseIndex = i;
          currentPhaseName.value = phases[i].name;
          
          // Trigger haptic if enabled
          if (phases[i].enableHaptic) {
            HapticFeedback.lightImpact();
          }
        }
        
        // Calculate time remaining in current phase
        final timeIntoPhase = elapsed - phaseStartTime;
        final phaseRemaining = phases[i].durationMs - timeIntoPhase;
        countdown.value = (phaseRemaining / 1000).ceil();
        
        break;
      }
      phaseStartTime = cumulativeTime;
    }

    notifyListeners();
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (_isDisposed) return;

    if (status == AnimationStatus.completed) {
      _cyclesCompleted++;
      currentCycle.value = _cyclesCompleted;

      if (repeatCount == 0 || _cyclesCompleted < repeatCount) {
        // Repeat cycle
        _animationController.reset();
        _animationController.forward();
        _startCountdownTimer();
      } else {
        // Complete
        _stopCountdownTimer();
        onComplete?.call();
      }
    }
  }

  void _startCountdownTimer() {
    // Countdown is now updated in _onAnimationUpdate based on current phase
    // Set initial countdown to first phase duration
    if (phases.isNotEmpty) {
      countdown.value = phases[0].durationSeconds.ceil();
    }
  }

  void _stopCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  /// Start with 3-2-1 pre-roll countdown
  void start() {
    isPreRoll.value = true;
    countdown.value = 3;
    currentPhaseName.value = 'Get Ready';

    int preRollCount = 3;
    _preRollTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }

      preRollCount--;
      countdown.value = preRollCount;

      if (preRollCount == 0) {
        timer.cancel();
        _startBreathing();
      }
    });
  }

  void _startBreathing() {
    isPreRoll.value = false;
    _currentPhaseIndex = 0;
    _cyclesCompleted = 0;
    currentCycle.value = 0;
    currentPhaseName.value = phases.isNotEmpty ? phases[0].name : '';

    _startCountdownTimer();
    _animationController.forward();
  }

  void pause() {
    _pausedAnimationValue = _animationController.value;
    _pausedCountdown = countdown.value;
    _animationController.stop();
    _stopCountdownTimer();
    _preRollTimer?.cancel();
  }

  void resume() {
    if (isPreRoll.value) {
      // Resume pre-roll (simplified - restart from current countdown)
      start();
    } else {
      // Resume animation from paused position
      _animationController.value = _pausedAnimationValue;
      countdown.value = _pausedCountdown;
      _animationController.forward();
      _startCountdownTimer();
    }
  }

  void stop() {
    _animationController.stop();
    _animationController.reset();
    _stopCountdownTimer();
    _preRollTimer?.cancel();
    isPreRoll.value = true;
    countdown.value = 0;
    currentPhaseName.value = '';
    _currentPhaseIndex = 0;
    _cyclesCompleted = 0;
    currentCycle.value = 0;
  }

  Animation<double> get scaleAnimation => _scaleAnimation;
  bool get isAnimating => _animationController.isAnimating;
  bool get isCompleted => _animationController.isCompleted;

  @override
  void dispose() {
    _isDisposed = true;
    _stopCountdownTimer();
    _preRollTimer?.cancel();
    _animationController.dispose();
    countdown.dispose();
    currentPhaseName.dispose();
    isPreRoll.dispose();
    currentCycle.dispose();
    super.dispose();
  }
}
