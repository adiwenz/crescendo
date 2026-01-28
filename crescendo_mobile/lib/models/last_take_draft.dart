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
  });
}
