import 'package:flutter/foundation.dart';
import 'pitch_frame.dart';

class LastTake {
  final String exerciseId;
  final DateTime recordedAt;
  final List<PitchFrame> frames;
  final double durationSec;
  final String? audioPath;
  final String? pitchDifficulty;
  final double? recorderStartSec;
  final double? offsetMs;
  final int? minMidi;
  final int? maxMidi;
  final String? referenceWavPath;
  final int? referenceSampleRate;
  final String? referenceWavSha1;

  LastTake({
    required this.exerciseId,
    required this.recordedAt,
    required this.frames,
    required this.durationSec,
    this.audioPath,
    this.pitchDifficulty,
    this.recorderStartSec,
    this.offsetMs,
    this.minMidi,
    this.maxMidi,
    this.referenceWavPath,
    this.referenceSampleRate,
    this.referenceWavSha1,
  });

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'recordedAt': recordedAt.toIso8601String(),
        'frames': frames.map((f) => f.toJson()).toList(),
        'durationSec': durationSec,
        'audioPath': audioPath,
        'pitchDifficulty': pitchDifficulty,
        'recorderStartSec': recorderStartSec,
        'offsetMs': offsetMs,
        'minMidi': minMidi,
        'maxMidi': maxMidi,
        'referenceWavPath': referenceWavPath,
        'referenceSampleRate': referenceSampleRate,
        'referenceWavSha1': referenceWavSha1,
      };

  factory LastTake.fromJson(Map<String, dynamic> json) {
    if (kDebugMode) {
      debugPrint('[LastTakeRead] rawMap=$json');
      debugPrint('[LastTakeRead] pitchDifficulty=${json['pitchDifficulty']} minMidi=${json['minMidi']} maxMidi=${json['maxMidi']}');
    }
    return LastTake(
        exerciseId: json['exerciseId'] as String,
        recordedAt: DateTime.parse(json['recordedAt'] as String),
        frames: (json['frames'] as List<dynamic>? ?? const [])
            .map((f) => PitchFrame.fromJson(f as Map<String, dynamic>))
            .toList(),
        durationSec: (json['durationSec'] as num).toDouble(),
        audioPath: json['audioPath'] as String?,
        pitchDifficulty: json['pitchDifficulty'] as String?,
        recorderStartSec: (json['recorderStartSec'] as num?)?.toDouble(),
        offsetMs: (json['offsetMs'] as num?)?.toDouble(),
        minMidi: (json['minMidi'] as num?)?.toInt(),
        maxMidi: (json['maxMidi'] as num?)?.toInt(),
        referenceWavPath: json['referenceWavPath'] as String?,
        referenceSampleRate: (json['referenceSampleRate'] as num?)?.toInt(),
        referenceWavSha1: json['referenceWavSha1'] as String?,
      );
  }
}
