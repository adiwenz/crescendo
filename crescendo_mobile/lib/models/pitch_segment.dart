class PitchSegment {
  final int startMs;
  final int endMs;
  final int midiNote;
  final double toleranceCents;
  final String? label;
  final int? startMidi;
  final int? endMidi;

  const PitchSegment({
    required this.startMs,
    required this.endMs,
    required this.midiNote,
    required this.toleranceCents,
    this.label,
    this.startMidi,
    this.endMidi,
  });

  bool get isGlide => startMidi != null && endMidi != null;
}
