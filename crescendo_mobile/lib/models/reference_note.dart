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

  ReferenceNote copyWith({
    double? startSec,
    double? endSec,
    int? midi,
    String? lyric,
    bool? isGlideStart,
    bool? isGlideEnd,
    int? glideEndMidi,
  }) {
    return ReferenceNote(
      startSec: startSec ?? this.startSec,
      endSec: endSec ?? this.endSec,
      midi: midi ?? this.midi,
      lyric: lyric ?? this.lyric,
      isGlideStart: isGlideStart ?? this.isGlideStart,
      isGlideEnd: isGlideEnd ?? this.isGlideEnd,
      glideEndMidi: glideEndMidi ?? this.glideEndMidi,
    );
  }
}
