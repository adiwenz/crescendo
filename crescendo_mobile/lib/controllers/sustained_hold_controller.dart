import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/pitch_frame.dart';
import '../utils/pitch_ball_controller.dart';
import '../utils/pitch_math.dart';

enum SustainedHoldState {
  intro,      // Initial check/countdown
  playing,    // Reference playing, user singing
  intermission, // Between notes
  review,     // Post-set review
}

class SustainedHoldController extends ChangeNotifier {
  // Config
  static const double snapThresholdCents = 30.0;
  static const double unsnapThresholdCents = 40.0;
  static const int notesInSet = 5;
  static const double noteDurationSec = 5.0;
  
  // State
  final ValueNotifier<SustainedHoldState> state = ValueNotifier(SustainedHoldState.intro);
  final ValueNotifier<int> currentNoteIndex = ValueNotifier(0); // 0 to 4
  final ValueNotifier<double> timeRemaining = ValueNotifier(noteDurationSec);
  
  // Pitch State
  final ValueNotifier<double> currentMidi = ValueNotifier(0.0);
  final ValueNotifier<double?> centsError = ValueNotifier(null);
  final ValueNotifier<bool> isSnapped = ValueNotifier(false);
  final ValueNotifier<double> stabilityScore = ValueNotifier(0.0); // 0.0 to 1.0 for current note
  
  // Internal
  final PitchBallController _pitchSmoother = PitchBallController();
  List<double> _targetMidis = [];
  double _targetMidi = 60.0; // Current target
  bool _wasSnapped = false;
  
  // Scoring / Stats
  double _timeSnapped = 0.0;
  double _timeTotal = 0.0;
  
  // Review Data
  // List of results for each note
  final List<SustainedNoteResult> _results = [];
  final List<PitchFrame> _currentNoteFrames = [];

  double get targetMidi => _targetMidi;
  List<SustainedNoteResult> get results => List.unmodifiable(_results);

  void init(List<double> targets) {
    _targetMidis = targets;
    if (_targetMidis.isEmpty) {
        // Fallback default C major pentatonic-ish build up
        _targetMidis = [60, 62, 64, 65, 67]; 
    }
    reset();
  }

  void reset() {
    state.value = SustainedHoldState.intro;
    currentNoteIndex.value = 0;
    _results.clear();
    _prepareNote(0);
  }

  void _prepareNote(int index) {
      if (index >= _targetMidis.length) {
          state.value = SustainedHoldState.review;
          return;
      }
      currentNoteIndex.value = index;
      _targetMidi = _targetMidis[index];
      timeRemaining.value = noteDurationSec;
      
      // Reset pitch state
      currentMidi.value = 0.0;
      centsError.value = null;
      isSnapped.value = false;
      stabilityScore.value = 0.0;
      _wasSnapped = false;
      _timeSnapped = 0.0;
      _timeTotal = 0.0;
      _pitchSmoother.reset();
      _currentNoteFrames.clear();
  }

  void startNote() {
      state.value = SustainedHoldState.playing;
  }
  
  void updateTime(double dt) {
      if (state.value != SustainedHoldState.playing) return;
      
      timeRemaining.value = (timeRemaining.value - dt).clamp(0.0, noteDurationSec);
      _timeTotal += dt;
      
      if (isSnapped.value) {
          _timeSnapped += dt;
      }
      
      stabilityScore.value = _timeTotal > 0 ? (_timeSnapped / _timeTotal) : 0.0;
      
      if (timeRemaining.value <= 0) {
          finishNote();
      }
  }

  void finishNote() {
      // Save result
      _results.add(SustainedNoteResult(
          targetMidi: _targetMidi,
          stability: stabilityScore.value,
          frames: List.from(_currentNoteFrames),
      ));
      
      if (currentNoteIndex.value < notesInSet - 1) {
          state.value = SustainedHoldState.intermission;
          // Could auto-advance or wait for UI
           _prepareNote(currentNoteIndex.value + 1);
      } else {
          state.value = SustainedHoldState.review;
      }
  }

  void processPitchFrame(PitchFrame frame) {
    if (state.value != SustainedHoldState.playing) return;

    final hz = frame.hz;
    final time = frame.time;

    // Store for review
    if (hz != null && hz > 0) {
        _currentNoteFrames.add(frame);
    }

    if (hz == null || hz <= 0) {
      // Silence handling could be added here
      return;
    }

    // Smooth the input
    final rawMidi = PitchMath.hzToMidi(hz);
    _pitchSmoother.addSample(timeSec: time, midi: rawMidi);
    
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
    }
  }
  
  @override
  void dispose() {
    state.dispose();
    currentNoteIndex.dispose();
    timeRemaining.dispose();
    currentMidi.dispose();
    centsError.dispose();
    isSnapped.dispose();
    stabilityScore.dispose();
    super.dispose();
  }
}

class SustainedNoteResult {
    final double targetMidi;
    final double stability;
    final List<PitchFrame> frames;
    
    SustainedNoteResult({
        required this.targetMidi,
        required this.stability,
        required this.frames,
    });
}
