import 'dart:async';
import 'dart:math' as math;

import '../models/pitch_frame.dart';
import 'loudness_meter.dart';

class HoldExerciseState {
  final double targetHz;
  final double toleranceCents;
  final double onPitchSeconds;
  final double progress;
  final double? centsError;
  final double rms;
  final bool success;

  const HoldExerciseState({
    required this.targetHz,
    required this.toleranceCents,
    required this.onPitchSeconds,
    required this.progress,
    required this.centsError,
    required this.rms,
    required this.success,
  });

  HoldExerciseState copyWith({
    double? targetHz,
    double? toleranceCents,
    double? onPitchSeconds,
    double? progress,
    double? centsError,
    double? rms,
    bool? success,
  }) {
    return HoldExerciseState(
      targetHz: targetHz ?? this.targetHz,
      toleranceCents: toleranceCents ?? this.toleranceCents,
      onPitchSeconds: onPitchSeconds ?? this.onPitchSeconds,
      progress: progress ?? this.progress,
      centsError: centsError ?? this.centsError,
      rms: rms ?? this.rms,
      success: success ?? this.success,
    );
  }
}

class HoldExerciseController {
  final double targetHz;
  final double toleranceCents;
  final double requiredHoldSec;
  final LoudnessMeter loudness;
  final void Function(HoldExerciseState) onState;

  double _onPitchAccum = 0;
  double _lastTime = 0;
  bool _running = false;

  HoldExerciseController({
    required this.targetHz,
    this.toleranceCents = 30,
    this.requiredHoldSec = 3.0,
    LoudnessMeter? loudness,
    required this.onState,
  }) : loudness = loudness ?? LoudnessMeter();

  void start() {
    _running = true;
    _onPitchAccum = 0;
    _lastTime = 0;
    _emit(centsError: null, rms: 0);
  }

  void stop() {
    _running = false;
  }

  /// Call this for each new pitch frame. Expects monotonic time (seconds).
  void addFrame(PitchFrame frame, {List<double>? rawBuffer}) {
    if (!_running) return;
    final dt = _lastTime == 0 ? 0 : math.max(0, frame.time - _lastTime);
    _lastTime = frame.time;

    double rms = loudness.addSamples(rawBuffer ?? const []);

    double? centsError;
    bool onPitch = false;
    if (frame.hz != null && frame.hz! > 0) {
      centsError = 1200 * (math.log(frame.hz! / targetHz) / math.ln2);
      onPitch = centsError.abs() <= toleranceCents;
    }

    if (onPitch) {
      _onPitchAccum += dt;
    } else {
      // If we drifted off for too long, reset accumulator.
      if (dt > 0.15) {
        _onPitchAccum = 0;
      }
    }

    final progress = (_onPitchAccum / requiredHoldSec).clamp(0.0, 1.0);
    final success = progress >= 1.0;
    if (success) _running = false;

    _emit(
      centsError: centsError,
      rms: rms,
      onPitchSeconds: _onPitchAccum,
      progress: progress,
      success: success,
    );
  }

  void _emit({
    double? centsError,
    required double rms,
    double? onPitchSeconds,
    double? progress,
    bool? success,
  }) {
    onState(
      HoldExerciseState(
        targetHz: targetHz,
        toleranceCents: toleranceCents,
        onPitchSeconds: onPitchSeconds ?? _onPitchAccum,
        progress: progress ?? (_onPitchAccum / requiredHoldSec).clamp(0.0, 1.0),
        centsError: centsError,
        rms: rms,
        success: success ?? false,
      ),
    );
  }
}
