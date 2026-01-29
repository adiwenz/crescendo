class ReferenceNote {
  final double startSec;
  final double endSec;
  final int midi;
  final String? lyric;
  final bool isGlideStart;
  final bool isGlideEnd;
  final int? glideEndMidi; // For glide start notes, the target end MIDI

  const ReferenceNote({
    required this.startSec,
    required this.endSec,
    required this.midi,
    this.lyric,
    this.isGlideStart = false,
    this.isGlideEnd = false,
    this.glideEndMidi,
  });

  bool get isGlide => isGlideStart || isGlideEnd;
  double get durationSec => endSec - startSec;
  String? get solfege => lyric;
}
