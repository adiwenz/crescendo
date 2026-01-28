class ExerciseTake {
  final String exerciseId;
  final DateTime createdAt;
  final double score;
  final String audioPath;
  final String pitchPath;
  final double offsetMs;
  final int? minMidi;
  final int? maxMidi;
  final String? referenceWavPath;
  final int? referenceSampleRate;
  final String? referenceWavSha1;
  final String? pitchDifficulty;

  const ExerciseTake({
    required this.exerciseId,
    required this.createdAt,
    required this.score,
    required this.audioPath,
    required this.pitchPath,
    required this.offsetMs,
    this.minMidi,
    this.maxMidi,
    this.referenceWavPath,
    this.referenceSampleRate,
    this.referenceWavSha1,
    this.pitchDifficulty,
  });

  Map<String, dynamic> toMap() => {
        'exerciseId': exerciseId,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'score': score,
        'audioPath': audioPath,
        'pitchPath': pitchPath,
        'offsetMs': offsetMs,
        'minMidi': minMidi,
        'maxMidi': maxMidi,
        'referenceWavPath': referenceWavPath,
        'referenceSampleRate': referenceSampleRate,
        'referenceWavSha1': referenceWavSha1,
        'pitchDifficulty': pitchDifficulty,
      };

  factory ExerciseTake.fromMap(Map<String, dynamic> m) {
    return ExerciseTake(
      exerciseId: m['exerciseId'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
      score: (m['score'] as num).toDouble(),
      audioPath: m['audioPath'] as String,
      pitchPath: m['pitchPath'] as String,
      offsetMs: (m['offsetMs'] as num).toDouble(),
      minMidi: (m['minMidi'] as num?)?.toInt(),
      maxMidi: (m['maxMidi'] as num?)?.toInt(),
      referenceWavPath: m['referenceWavPath'] as String?,
      referenceSampleRate: (m['referenceSampleRate'] as num?)?.toInt(),
      referenceWavSha1: m['referenceWavSha1'] as String?,
      pitchDifficulty: m['pitchDifficulty'] as String?,
    );
  }
}
