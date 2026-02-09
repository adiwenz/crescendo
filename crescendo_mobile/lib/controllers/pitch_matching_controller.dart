import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/pitch_frame.dart';
import '../utils/pitch_ball_controller.dart';
import '../utils/pitch_math.dart';

enum PitchMatchState {
  idle,
  playingReference,
  listening, // Waiting for user input
  singing, // User is singing
  matched, // Successfully matched
  review, // Post-exercise review
}

class PitchMatchingController extends ChangeNotifier {
  // Config
  static const double snapThresholdCents = 30.0;
  static const double unsnapThresholdCents = 40.0;
  static const double matchHoldDurationSec = 0.5; // Required hold time for match

  // State
  final ValueNotifier<PitchMatchState> state = ValueNotifier(PitchMatchState.idle);
  final ValueNotifier<double> currentMidi = ValueNotifier(0.0);
  final ValueNotifier<double?> centsError = ValueNotifier(null);
  final ValueNotifier<bool> isSnapped = ValueNotifier(false);
  final ValueNotifier<double> matchProgress = ValueNotifier(0.0); // 0.0 to 1.0

  // Internal
  final PitchBallController _pitchSmoother = PitchBallController();
  double _targetMidi = 60.0;
  double _timeSnapped = 0.0;
  bool _wasSnapped = false;
  
  // For review
  final List<PitchFrame> _sessionFrames = [];
  double _startTimeSec = 0.0;

  double get targetMidi => _targetMidi;

  void setTargetMidi(double midi) {
    _targetMidi = midi;
    reset();
  }

  void reset() {
    state.value = PitchMatchState.idle;
    currentMidi.value = 0.0;
    centsError.value = null;
    isSnapped.value = false;
    matchProgress.value = 0.0;
    _pitchSmoother.reset();
    _wasSnapped = false;
    _timeSnapped = 0.0;
    _sessionFrames.clear();
  }

  void startSession() {
     state.value = PitchMatchState.listening;
     _startTimeSec = DateTime.now().millisecondsSinceEpoch / 1000.0;
  }

  void processPitchFrame(PitchFrame frame) {
    if (state.value == PitchMatchState.idle || 
        state.value == PitchMatchState.playingReference ||
        state.value == PitchMatchState.review) {
      return;
    }

    final hz = frame.hz;
    final time = frame.time;

    // Store for review
    if (hz != null && hz > 0) {
        _sessionFrames.add(frame);
    }

    if (hz == null || hz <= 0) {
      // Logic for silence?
      // For now just keep last known or reset?
      // If silence is too long, maybe unsnap?
      // Lets rely on voice probability if available, otherwise hz
      return;
    }

    // Smooth the input
    final rawMidi = PitchMath.hzToMidi(hz);
    _pitchSmoother.addSample(timeSec: time, midi: rawMidi);
    
    // Get smoothed value (may need to request specific time, but last sample is fine for real-time)
    // PitchBallController calculates smoothed value on addSample usually, but let's use valueAt with current time
    // heavily filtered for stability
    final smoothedMidi = _pitchSmoother.lastSampleMidi ?? rawMidi;
    currentMidi.value = smoothedMidi;

    // Calculate error
    final error = (smoothedMidi - _targetMidi) * 100.0;
    centsError.value = error;

    // Snapping Logic
    final absError = error.abs();
    bool snapped = _wasSnapped;

    if (_wasSnapped) {
      // Hysteresis: stay snapped until error > 40
      if (absError > unsnapThresholdCents) {
        snapped = false;
      }
    } else {
      // Snap if error <= 30
      if (absError <= snapThresholdCents) {
        snapped = true;
      }
    }

    // Update Snapped State
    if (snapped != _wasSnapped) {
      _wasSnapped = snapped;
      isSnapped.value = snapped;
      if (!snapped) {
        _timeSnapped = 0.0;
        matchProgress.value = 0.0;
      }
    }

    // Match Progress (Call & Response or Sing Along)
    if (snapped) {
        // Accumulate time? Or just visual feedback?
        // For general "Match" feeling:
        state.value = PitchMatchState.singing;
        
        // Simple progress accumulator (simulated delta time)
        // Ideally we'd valid delta time from frames
        // Assuming ~60fps or frame rate
        // We can use frame.time difference if we tracked last frame time
        
        // Note: frame.time is typically from start of recording.
        // We need a delta.
        // For now, let's just use a simple increment if we don't have delta easily
        // But better to be robust.
        // The service usually sends frames every ~10-20ms.
    }
  }
  
  // Method to manually set state (e.g. from UI)
  void setState(PitchMatchState newState) {
      state.value = newState;
  }
  
  @override
  void dispose() {
    state.dispose();
    currentMidi.dispose();
    centsError.dispose();
    isSnapped.dispose();
    matchProgress.dispose();
    super.dispose();
  }
}
