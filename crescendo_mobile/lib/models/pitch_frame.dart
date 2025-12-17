class PitchFrame {
  final double time;
  final double? hz;
  final double? midi;
  final double? centsError;
  final double? voicedProb;
  final double? rms;

  PitchFrame({
    required this.time,
    this.hz,
    this.midi,
    this.centsError,
    this.voicedProb,
    this.rms,
  });

  double? _safe(double? v) {
    if (v == null) return null;
    if (v.isNaN || v.isInfinite) return null;
    return v;
  }

  Map<String, dynamic> toJson() => {
        "time": time,
        "hz": _safe(hz),
        "midi": _safe(midi),
        "centsError": _safe(centsError),
        "voicedProb": _safe(voicedProb),
        "rms": _safe(rms),
      };

  factory PitchFrame.fromJson(Map<String, dynamic> json) => PitchFrame(
        time: (json["time"] as num).toDouble(),
        hz: (json["hz"] as num?)?.toDouble(),
        midi: (json["midi"] as num?)?.toDouble(),
        centsError: (json["centsError"] as num?)?.toDouble(),
        voicedProb: (json["voicedProb"] as num?)?.toDouble(),
        rms: (json["rms"] as num?)?.toDouble(),
      );
}
