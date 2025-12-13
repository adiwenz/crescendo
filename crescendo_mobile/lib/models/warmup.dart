import 'dart:math' as math;

class NoteSegment {
  final double start;
  final double end;
  final double targetMidi;

  NoteSegment({required this.start, required this.end, required this.targetMidi});

  Map<String, dynamic> toJson() => {"start": start, "end": end, "targetMidi": targetMidi};

  factory NoteSegment.fromJson(Map<String, dynamic> json) => NoteSegment(
        start: (json["start"] as num).toDouble(),
        end: (json["end"] as num).toDouble(),
        targetMidi: (json["targetMidi"] as num).toDouble(),
      );
}

class WarmupDefinition {
  final String id;
  final String name;
  final List<String> notes;
  final List<double> durations;
  final double gap;
  final bool glide;

  WarmupDefinition({
    required this.id,
    required this.name,
    required this.notes,
    required this.durations,
    this.gap = 0.0,
    this.glide = false,
  });

  List<NoteSegment> buildPlan() {
    final segments = <NoteSegment>[];
    double t = 0;
    for (var i = 0; i < notes.length; i++) {
      final midi = noteToMidi(notes[i]);
      final dur = durations[i];
      segments.add(NoteSegment(start: t, end: t + dur, targetMidi: midi));
      t += dur + gap;
    }
    return segments;
  }

  double get totalDuration => durations.fold(0.0, (p, e) => p + e) + gap * (durations.length - 1);

  static double noteToMidi(String note) {
    final match = RegExp(r'^([A-G])(#|b)?(\d)$').firstMatch(note);
    if (match == null) return 60;
    const order = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
    final base = order[match.group(1)] ?? 0;
    final acc = match.group(2) == '#' ? 1 : match.group(2) == 'b' ? -1 : 0;
    final octave = int.parse(match.group(3)!);
    return (octave + 1) * 12 + base + acc;
  }
}

class WarmupsLibrary {
  static final defaults = <WarmupDefinition>[
    WarmupDefinition(
      id: 'c_scale_legato',
      name: 'C Major Scale (0.5s notes, 0.1s gaps)',
      notes: const ['C4', 'D4', 'E4', 'F4', 'G4', 'A4', 'B4', 'C5'],
      durations: List.filled(8, 0.5),
      gap: 0.1,
    ),
    WarmupDefinition(
      id: 'c_scale_staccato',
      name: 'C Major Scale (staccato)',
      notes: const ['C4', 'D4', 'E4', 'F4', 'G4', 'A4', 'B4', 'C5'],
      durations: List.filled(8, 0.3),
      gap: 0.2,
    ),
    WarmupDefinition(
      id: 'c_slide',
      name: 'Slide: C → G → C',
      notes: const ['C4', 'G4', 'C4'],
      durations: const [0.8, 0.8, 0.4],
      gap: 0.0,
      glide: true,
    ),
  ];
}

double midiToHz(double midi) => 440.0 * math.pow(2, (midi - 69.0) / 12.0);
