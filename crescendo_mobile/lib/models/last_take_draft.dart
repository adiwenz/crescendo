class LastTakeDraft {
  final String exerciseId;
  final int score;
  final String pitchPath;
  final String pcmPath;
  final Future<String> wavPathFuture;
  final int offsetMs;
  final int durationMs;
  final DateTime createdAt;
  final String? contourJson;
  final int? minMidi;
  final int? maxMidi;
  final String? referenceWavPath;
  final int? referenceSampleRate;
  final String? referenceWavSha1;
  final int pcmBytesWritten; // Authoritative byte count from worker

  LastTakeDraft({
    required this.exerciseId,
    required this.score,
    required this.pitchPath,
    required this.pcmPath,
    required this.wavPathFuture,
    required this.offsetMs,
    required this.durationMs,
    required this.createdAt,
    this.contourJson,
    this.minMidi,
    this.maxMidi,
    this.referenceWavPath,
    this.referenceSampleRate,
    this.referenceWavSha1,
    required this.pcmBytesWritten,
  });
}
