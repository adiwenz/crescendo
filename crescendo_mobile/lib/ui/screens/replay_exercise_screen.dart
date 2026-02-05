import 'package:flutter/material.dart';

import '../../models/audio_sync_info.dart';
import '../../models/replay_models.dart';
import '../widgets/pitch_highway_replay.dart';

class ReplayExerciseScreen extends StatelessWidget {
  final String title;
  final List<TargetNote> targetNotes;
  final List<PitchSample> recordedSamples;
  final int takeDurationMs;
  final String? referencePath;
  final String? recordingPath;
  final AudioSyncInfo? syncInfo;

  const ReplayExerciseScreen({
    super.key,
    required this.title,
    required this.targetNotes,
    required this.recordedSamples,
    required this.takeDurationMs,
    this.referencePath,
    this.recordingPath,
    this.syncInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: PitchHighwayReplay(
          targetNotes: targetNotes,
          recordedSamples: recordedSamples,
          takeDurationMs: takeDurationMs,
          referencePath: referencePath,
          recordingPath: recordingPath,
          syncInfo: syncInfo,
        ),
      ),
    );
  }
}
