class Metrics {
  final double score;
  final double meanAbsCents;
  final double pctWithin20;
  final double pctWithin50;
  final int validFrames;

  Metrics({
    required this.score,
    required this.meanAbsCents,
    required this.pctWithin20,
    required this.pctWithin50,
    required this.validFrames,
  });

  Map<String, dynamic> toJson() => {
        "score": score,
        "meanAbsCents": meanAbsCents,
        "pctWithin20": pctWithin20,
        "pctWithin50": pctWithin50,
        "validFrames": validFrames,
      };

  factory Metrics.fromJson(Map<String, dynamic> json) => Metrics(
        score: (json["score"] as num).toDouble(),
        meanAbsCents: (json["meanAbsCents"] as num).toDouble(),
        pctWithin20: (json["pctWithin20"] as num).toDouble(),
        pctWithin50: (json["pctWithin50"] as num).toDouble(),
        validFrames: (json["validFrames"] as num).toInt(),
      );
}
