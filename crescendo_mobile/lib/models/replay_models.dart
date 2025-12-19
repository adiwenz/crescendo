class TargetNote {
  final int startMs;
  final int endMs;
  final double midi;
  final String? label;

  const TargetNote({
    required this.startMs,
    required this.endMs,
    required this.midi,
    this.label,
  });
}

class PitchSample {
  final int timeMs;
  final double? midi;
  final double? freqHz;

  const PitchSample({
    required this.timeMs,
    this.midi,
    this.freqHz,
  });
}
