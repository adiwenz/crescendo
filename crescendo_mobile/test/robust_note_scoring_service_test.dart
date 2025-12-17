import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:crescendo_mobile/models/pitch_frame.dart';
import 'package:crescendo_mobile/models/reference_note.dart';
import 'package:crescendo_mobile/services/robust_note_scoring_service.dart';

double _midiToHz(int midi) {
  return 440.0 * math.pow(2.0, (midi - 69) / 12.0);
}

double _centsError(double f0Hz, double targetHz) {
  return 1200.0 * (math.log(f0Hz / targetHz) / math.ln2);
}

ReferenceNote? _noteAt(List<ReferenceNote> notes, double t) {
  for (final n in notes) {
    if (t >= n.startSec && t <= n.endSec) return n;
  }
  return null;
}

double _oldFrameScore(List<ReferenceNote> notes, List<PitchFrame> frames) {
  final errors = <double>[];
  for (final f in frames) {
    final note = _noteAt(notes, f.time);
    if (note == null) continue;
    final hz = f.hz;
    if (hz == null || hz <= 0) continue;
    final targetHz = _midiToHz(note.midi);
    errors.add(_centsError(hz, targetHz).abs());
  }
  if (errors.isEmpty) return 0.0;
  final mean = errors.reduce((a, b) => a + b) / errors.length;
  return 100.0 * (1.0 - math.min(mean / 100.0, 1.0));
}

void main() {
  test('robust scoring handles drift, vibrato, and consonants', () {
    final notes = [
      const ReferenceNote(startSec: 0.0, endSec: 1.0, midi: 60),
      const ReferenceNote(startSec: 1.0, endSec: 2.0, midi: 62),
      const ReferenceNote(startSec: 2.0, endSec: 3.0, midi: 64),
    ];

    const hopSec = 0.02;
    const totalSec = 3.2;
    const lateSec = 0.08;
    const vibratoCents = 30.0;
    const vibratoHz = 5.0;
    const boundaryUnvoicedSec = 0.04;

    final frames = <PitchFrame>[];
    final frameCount = (totalSec / hopSec).floor() + 1;
    for (var i = 0; i < frameCount; i++) {
      final t = i * hopSec;
      final actualT = t - lateSec;
      final note = _noteAt(notes, actualT);
      if (note == null) {
        frames.add(PitchFrame(time: t, hz: 0, midi: null, voicedProb: 0.0, rms: 0.0));
        continue;
      }
      if (actualT < note.startSec + boundaryUnvoicedSec ||
          actualT > note.endSec - boundaryUnvoicedSec) {
        frames.add(PitchFrame(time: t, hz: 0, midi: null, voicedProb: 0.2, rms: 0.01));
        continue;
      }
      final targetHz = _midiToHz(note.midi);
      final cents = vibratoCents * math.sin(2 * math.pi * vibratoHz * t);
      final hz = targetHz * math.pow(2.0, cents / 1200.0);
      frames.add(PitchFrame(time: t, hz: hz, midi: null, voicedProb: 0.95, rms: 0.1));
    }

    final robust = RobustNoteScoringService().score(notes: notes, frames: frames);
    final oldScore = _oldFrameScore(notes, frames);

    expect(robust.overallScorePct, greaterThanOrEqualTo(90));
    expect(oldScore, lessThan(90));

    // ignore: avoid_print
    print('old score: ${oldScore.toStringAsFixed(1)} new score: ${robust.overallScorePct.toStringAsFixed(1)}');
    for (final note in robust.noteScores) {
      // ignore: avoid_print
      print('note ${note.index} median=${note.medianErrorCents} mad=${note.madCents} score=${note.score}');
    }
  });
}
