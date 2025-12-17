import 'dart:math' as math;

import '../models/pitch_frame.dart';
import '../models/reference_note.dart';

class RobustScoringConfig {
  final double voicedThreshold;
  final double rmsThreshold;
  final double attackTrimMs;
  final double releaseTrimMs;
  final double timingToleranceMs;
  final double perfectCents;
  final double goodCents;
  final double okCents;
  final double badCents;
  final double stabilityMadLimit;
  final double stabilityPenaltyMultiplier;
  final bool enableOctaveRescue;
  final double octaveBandCents;
  final double minNoteWeightSec;

  const RobustScoringConfig({
    this.voicedThreshold = 0.6,
    this.rmsThreshold = 0.02,
    this.attackTrimMs = 80,
    this.releaseTrimMs = 80,
    this.timingToleranceMs = 120,
    this.perfectCents = 25,
    this.goodCents = 50,
    this.okCents = 80,
    this.badCents = 120,
    this.stabilityMadLimit = 35,
    this.stabilityPenaltyMultiplier = 0.85,
    this.enableOctaveRescue = true,
    this.octaveBandCents = 80,
    this.minNoteWeightSec = 0.15,
  });
}

class RobustNoteScore {
  final int index;
  final int midiNumber;
  final double startTime;
  final double endTime;
  final double? medianErrorCents;
  final double? madCents;
  final double? avgAbsCents;
  final double? medianAbsCents;
  final double? maxAbsCents;
  final double score;
  final String? reason;

  const RobustNoteScore({
    required this.index,
    required this.midiNumber,
    required this.startTime,
    required this.endTime,
    required this.medianErrorCents,
    required this.madCents,
    required this.avgAbsCents,
    required this.medianAbsCents,
    required this.maxAbsCents,
    required this.score,
    this.reason,
  });

  Map<String, dynamic> toJson() => {
        "i": index,
        "midi_number": midiNumber,
        "start_time": startTime,
        "end_time": endTime,
        "median_error_cents": medianErrorCents,
        "mad_cents": madCents,
        "avg_abs_cents": avgAbsCents,
        "median_abs_cents": medianAbsCents,
        "max_abs_cents": maxAbsCents,
        "score": score,
        if (reason != null) "reason": reason,
      };
}

class IgnoredFramesStats {
  final int totalFrames;
  final int voicedFiltered;
  final int rmsFiltered;
  final int trimFiltered;

  const IgnoredFramesStats({
    required this.totalFrames,
    required this.voicedFiltered,
    required this.rmsFiltered,
    required this.trimFiltered,
  });

  Map<String, dynamic> toJson() => {
        "total_frames": totalFrames,
        "voiced_filtered": voicedFiltered,
        "rms_filtered": rmsFiltered,
        "trim_filtered": trimFiltered,
      };
}

class RobustScoreResult {
  final double overallScorePct;
  final List<RobustNoteScore> noteScores;
  final IgnoredFramesStats ignoredFramesStats;

  const RobustScoreResult({
    required this.overallScorePct,
    required this.noteScores,
    required this.ignoredFramesStats,
  });

  Map<String, dynamic> toJson() => {
        "overall_score_pct": overallScorePct,
        "note_scores": noteScores.map((n) => n.toJson()).toList(),
        "ignored_frames_stats": ignoredFramesStats.toJson(),
      };
}

class RobustNoteScoringService {
  RobustScoreResult score({
    required List<ReferenceNote> notes,
    required List<PitchFrame> frames,
    RobustScoringConfig config = const RobustScoringConfig(),
    double offsetSec = 0.0,
  }) {
    final samples = frames
        .map((f) => _FrameSample(
              time: f.time - offsetSec,
              hz: f.hz,
              voicedProb: f.voicedProb ??
                  ((f.hz != null && f.hz! > 0) ? 1.0 : 0.0),
              rms: f.rms ?? 1.0,
            ))
        .where((s) => s.time.isFinite)
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    var voicedFiltered = 0;
    var rmsFiltered = 0;
    for (final s in samples) {
      if (s.voicedProb < config.voicedThreshold) voicedFiltered++;
      if (s.rms < config.rmsThreshold) rmsFiltered++;
    }

    final attackTrimSec = config.attackTrimMs / 1000.0;
    final releaseTrimSec = config.releaseTrimMs / 1000.0;
    final toleranceSec = config.timingToleranceMs / 1000.0;

    final noteScores = <RobustNoteScore>[];
    var weightedSum = 0.0;
    var weightTotal = 0.0;
    var trimFiltered = 0;

    for (var i = 0; i < notes.length; i++) {
      final note = notes[i];
      final start = note.startSec;
      final end = note.endSec;
      final midiNumber = note.midi;
      final targetHz = _midiToHz(midiNumber);

      final trimStart = start + attackTrimSec;
      final trimEnd = end - releaseTrimSec;
      final trimmedDuration = math.max(0.0, trimEnd - trimStart);

      final expandedStart = trimStart - toleranceSec;
      final expandedEnd = trimEnd + toleranceSec;

      final centsErrors = <double>[];
      final absErrors = <double>[];
      for (final s in samples) {
        final t = s.time;
        if (t < expandedStart || t > expandedEnd) continue;
        if (s.voicedProb < config.voicedThreshold) continue;
        if (s.rms < config.rmsThreshold) continue;
        if (t >= start && t <= end && (t < trimStart || t > trimEnd)) {
          trimFiltered++;
          continue;
        }
        final hz = s.hz;
        if (hz == null || hz <= 0 || !hz.isFinite) continue;
        final cents = _centsError(hz, targetHz);
        if (!cents.isFinite) continue;
        centsErrors.add(cents);
        absErrors.add(cents.abs());
      }

      final weight = math.max(trimmedDuration, config.minNoteWeightSec);

      if (centsErrors.isEmpty) {
        noteScores.add(RobustNoteScore(
          index: i,
          midiNumber: midiNumber,
          startTime: start,
          endTime: end,
          medianErrorCents: null,
          madCents: null,
          avgAbsCents: null,
          medianAbsCents: null,
          maxAbsCents: null,
          score: 0.0,
          reason: "no_valid_frames",
        ));
        weightTotal += weight;
        continue;
      }

      final medianError = _median(centsErrors);
      final mad = _mad(centsErrors, medianError);
      final avgAbs = absErrors.reduce((a, b) => a + b) / absErrors.length;
      final medianAbs = _median(absErrors);
      final maxAbs = absErrors.reduce(math.max);

      var scoringError = medianError;
      if (config.enableOctaveRescue) {
        final absErr = medianError.abs();
        if (absErr >= 1200.0 - config.octaveBandCents &&
            absErr <= 1200.0 + config.octaveBandCents) {
          scoringError =
              medianError > 0 ? medianError - 1200.0 : medianError + 1200.0;
        }
      }

      var noteScore = _tieredScore(scoringError.abs(), config);
      if (mad > config.stabilityMadLimit) {
        noteScore *= config.stabilityPenaltyMultiplier;
      }

      noteScores.add(RobustNoteScore(
        index: i,
        midiNumber: midiNumber,
        startTime: start,
        endTime: end,
        medianErrorCents: medianError,
        madCents: mad,
        avgAbsCents: avgAbs,
        medianAbsCents: medianAbs,
        maxAbsCents: maxAbs,
        score: noteScore,
      ));

      weightedSum += noteScore * weight;
      weightTotal += weight;
    }

    final overallScorePct =
        weightTotal > 0 ? (weightedSum / weightTotal) * 100.0 : 0.0;

    return RobustScoreResult(
      overallScorePct: overallScorePct,
      noteScores: noteScores,
      ignoredFramesStats: IgnoredFramesStats(
        totalFrames: samples.length,
        voicedFiltered: voicedFiltered,
        rmsFiltered: rmsFiltered,
        trimFiltered: trimFiltered,
      ),
    );
  }

  double _midiToHz(int midiNumber) {
    return 440.0 * math.pow(2.0, (midiNumber - 69) / 12.0);
  }

  double _centsError(double f0Hz, double targetHz) {
    return 1200.0 * (math.log(f0Hz / targetHz) / math.ln2);
  }

  double _tieredScore(double absCents, RobustScoringConfig config) {
    if (absCents <= config.perfectCents) return 1.0;
    if (absCents <= config.goodCents) return 0.75;
    if (absCents <= config.okCents) return 0.5;
    if (absCents <= config.badCents) return 0.25;
    return 0.0;
  }

  double _median(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  double _mad(List<double> values, double medianValue) {
    final deviations = values.map((v) => (v - medianValue).abs()).toList();
    return _median(deviations);
  }
}

class _FrameSample {
  final double time;
  final double? hz;
  final double voicedProb;
  final double rms;

  const _FrameSample({
    required this.time,
    required this.hz,
    required this.voicedProb,
    required this.rms,
  });
}
