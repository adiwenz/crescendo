import 'dart:convert';

import 'audio_sync_info.dart';
import 'metrics.dart';
import 'pitch_frame.dart';

class Take {
  final int? id;
  final String name;
  final DateTime createdAt;
  final String warmupId;
  final String warmupName;
  final String audioPath;
  final List<PitchFrame> frames;
  final Metrics metrics;
  final AudioSyncInfo? syncInfo;

  Take({
    this.id,
    required this.name,
    required this.createdAt,
    required this.warmupId,
    required this.warmupName,
    required this.audioPath,
    required this.frames,
    required this.metrics,
    this.syncInfo,
  });

  Map<String, dynamic> toMap() => {
        "id": id,
        "name": name,
        "createdAt": createdAt.toIso8601String(),
        "warmupId": warmupId,
        "warmupName": warmupName,
        "audioPath": audioPath,
        "framesJson": jsonEncode(frames.map((f) => f.toJson()).toList()),
        "metricsJson": jsonEncode(metrics.toJson()),
        if (syncInfo != null) "syncInfoJson": jsonEncode(syncInfo!.toMap()),
      };

  factory Take.fromMap(Map<String, dynamic> map) => Take(
        id: map["id"] as int?,
        name: map["name"] as String,
        createdAt: DateTime.parse(map["createdAt"] as String),
        warmupId: map["warmupId"] as String,
        warmupName: map["warmupName"] as String,
        audioPath: map["audioPath"] as String,
        frames: (jsonDecode(map["framesJson"] as String) as List<dynamic>)
            .map((e) => PitchFrame.fromJson(e as Map<String, dynamic>))
            .toList(),
        metrics: Metrics.fromJson(jsonDecode(map["metricsJson"] as String) as Map<String, dynamic>),
        syncInfo: map["syncInfoJson"] != null
            ? AudioSyncInfo.fromMap(jsonDecode(map["syncInfoJson"] as String) as Map<String, dynamic>)
            : null,
      );
}
