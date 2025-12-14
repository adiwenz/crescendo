class ReferenceNote {
  final double startSec;
  final double endSec;
  final int midi;
  final String? lyric;

  const ReferenceNote({
    required this.startSec,
    required this.endSec,
    required this.midi,
    this.lyric,
  });
}
