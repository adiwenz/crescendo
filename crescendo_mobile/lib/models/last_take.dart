import 'pitch_frame.dart';

class LastTake {
  final String exerciseId;
  final DateTime recordedAt;
  final List<PitchFrame> frames;
  final double durationSec;
  final String? audioPath;
  final String? pitchDifficulty;
  final double? recorderStartSec;

  LastTake({
    required this.exerciseId,
    required this.recordedAt,
    required this.frames,
    required this.durationSec,
    this.audioPath,
    this.pitchDifficulty,
    this.recorderStartSec,
  });

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'recordedAt': recordedAt.toIso8601String(),
        'frames': frames.map((f) => f.toJson()).toList(),
        'durationSec': durationSec,
        'audioPath': audioPath,
        'pitchDifficulty': pitchDifficulty,
        'recorderStartSec': recorderStartSec,
      };

  factory LastTake.fromJson(Map<String, dynamic> json) => LastTake(
        exerciseId: json['exerciseId'] as String,
        recordedAt: DateTime.parse(json['recordedAt'] as String),
        frames: (json['frames'] as List<dynamic>? ?? const [])
            .map((f) => PitchFrame.fromJson(f as Map<String, dynamic>))
            .toList(),
        durationSec: (json['durationSec'] as num).toDouble(),
        audioPath: json['audioPath'] as String?,
        pitchDifficulty: json['pitchDifficulty'] as String?,
        recorderStartSec: (json['recorderStartSec'] as num?)?.toDouble(),
      );
}
