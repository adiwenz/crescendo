class PitchFrame {
  final double time;
  final double? hz;
  final double? midi;
  final double? centsError;

  PitchFrame({required this.time, this.hz, this.midi, this.centsError});

  Map<String, dynamic> toJson() => {
        "time": time,
        "hz": hz,
        "midi": midi,
        "centsError": centsError,
      };

  factory PitchFrame.fromJson(Map<String, dynamic> json) => PitchFrame(
        time: (json["time"] as num).toDouble(),
        hz: (json["hz"] as num?)?.toDouble(),
        midi: (json["midi"] as num?)?.toDouble(),
        centsError: (json["centsError"] as num?)?.toDouble(),
      );
}
