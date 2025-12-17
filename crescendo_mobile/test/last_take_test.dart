import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crescendo_mobile/models/last_take.dart';
import 'package:crescendo_mobile/models/pitch_frame.dart';
import 'package:crescendo_mobile/services/last_take_store.dart';

void main() {
  test('LastTake serializes and deserializes', () {
    final take = LastTake(
      exerciseId: 'ex_1',
      recordedAt: DateTime.parse('2024-01-01T00:00:00Z'),
      durationSec: 5.5,
      frames: [
        PitchFrame(time: 0.1, hz: 440.0, midi: 69.0, voicedProb: 0.8, rms: 0.2),
      ],
      audioPath: '/tmp/audio.wav',
      pitchDifficulty: 'medium',
    );
    final decoded = LastTake.fromJson(take.toJson());
    expect(decoded.exerciseId, take.exerciseId);
    expect(decoded.durationSec, take.durationSec);
    expect(decoded.audioPath, take.audioPath);
    expect(decoded.pitchDifficulty, take.pitchDifficulty);
    expect(decoded.frames.length, 1);
    expect(decoded.frames.first.hz, 440.0);
    expect(decoded.frames.first.midi, 69.0);
  });

  test('LastTakeStore saves and loads', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LastTakeStore();
    final take = LastTake(
      exerciseId: 'ex_2',
      recordedAt: DateTime.parse('2024-01-02T00:00:00Z'),
      durationSec: 3.2,
      frames: [
        PitchFrame(time: 0.2, hz: 220.0, midi: 57.0),
      ],
    );
    await store.saveLastTake(take);
    final loaded = await store.getLastTake('ex_2');
    expect(loaded, isNotNull);
    expect(loaded!.frames.length, 1);
    expect(loaded.frames.first.midi, 57.0);
  });
}
