import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../models/pitch_frame.dart';
import '../../models/take.dart';
import '../../models/warmup.dart';
import '../../services/audio_synth_service.dart';
import '../../services/recording_service.dart';
import '../../services/scoring_service.dart';
import '../../services/storage/take_repository.dart';
import '../state.dart';
import '../widgets/metric_card.dart';
import '../widgets/pitch_graph.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final synth = AudioSynthService();
  final recordingService = RecordingService();
  final scoring = ScoringService();
  final repo = TakeRepository();
  final appState = AppState();

  bool recording = false;
  String? recordedPath;
  List<PitchFrame> frames = [];
  MetricsDisplay? metrics;
  final AudioPlayer _player = AudioPlayer();
  double playhead = 0;
  StreamSubscription? _posSub;
  StreamSubscription<PitchFrame>? _liveSub;
  final List<PitchFrame> _pendingFrames = [];
  Timer? _frameFlush;
  StreamSubscription<void>? _referenceDoneSub;
  Timer? _autoStopTimer;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    unawaited(_player.setVolume(1.0));
    _posSub = _player.onPositionChanged.listen((p) {
      setState(() => playhead = p.inMilliseconds / 1000.0);
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _liveSub?.cancel();
    _frameFlush?.cancel();
    _referenceDoneSub?.cancel();
    _autoStopTimer?.cancel();
    unawaited(synth.stop());
    _player.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    setState(() {
      recording = true;
      recordedPath = null;
      frames = [];
      metrics = null;
    });
    _liveSub?.cancel();
    _frameFlush?.cancel();
    _referenceDoneSub?.cancel();
    _autoStopTimer?.cancel();
    _liveSub = recordingService.liveStream.listen((pf) {
      _pendingFrames.add(pf);
      _scheduleFrameFlush();
    });
    await recordingService.start();
    final warmup = appState.selectedWarmup.value;
    if (_hasReference(warmup)) {
      await _playReferenceWithAutoStop(warmup);
    }
  }

  Future<void> _stopRecording() async {
    if (_stopping) return;
    _stopping = true;
    _referenceDoneSub?.cancel();
    _autoStopTimer?.cancel();
    await synth.stop();
    final result = await recordingService.stop();
    await _liveSub?.cancel();
    _frameFlush?.cancel();
    final warmup = appState.selectedWarmup.value;
    final refSegments = warmup.buildPlan();
    final enriched = _attachCents(result.frames, refSegments);
    final m = scoring.score(enriched);
    setState(() {
      recording = false;
      recordedPath = result.audioPath;
      frames = enriched;
      metrics = MetricsDisplay.fromMetrics(m);
    });
    _stopping = false;
  }

  Future<void> _saveTake() async {
    if (recordedPath == null || metrics == null) return;
    final warmup = appState.selectedWarmup.value;
    // Sanitize frames to avoid NaN in JSON.
    final cleanFrames = frames
        .map((f) => PitchFrame(time: f.time, hz: f.hz, midi: f.midi, centsError: f.centsError))
        .toList();
    final take = Take(
      name: 'Take ${DateTime.now().toLocal()}',
      createdAt: DateTime.now(),
      warmupId: warmup.id,
      warmupName: warmup.name,
      audioPath: recordedPath!,
      frames: cleanFrames,
      metrics: scoring.score(cleanFrames),
    );
    await repo.insert(take);
    appState.takesVersion.value++;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved take')));
    }
  }

  void _scheduleFrameFlush() {
    if (_frameFlush?.isActive ?? false) return;
    _frameFlush = Timer(const Duration(milliseconds: 16), () {
      if (_pendingFrames.isEmpty) return;
      final toAdd = List<PitchFrame>.from(_pendingFrames);
      _pendingFrames.clear();
      setState(() {
        frames = [...frames, ...toAdd];
      });
    });
  }

  bool _hasReference(WarmupDefinition warmup) => warmup.notes.isNotEmpty;

  Future<void> _playReferenceWithAutoStop(WarmupDefinition warmup) async {
    _referenceDoneSub?.cancel();
    final path = await synth.renderWarmup(warmup);
    await synth.playFile(path);
    _referenceDoneSub = synth.onComplete.listen((_) => _scheduleAutoStop());
    final fallbackDelay = Duration(milliseconds: (warmup.totalDuration * 1000).round() + 500);
    _autoStopTimer = Timer(fallbackDelay, _scheduleAutoStop);
  }

  void _scheduleAutoStop() {
    if (!recording || _stopping) return;
    _autoStopTimer?.cancel();
    _autoStopTimer = Timer(const Duration(milliseconds: 500), () {
      if (!recording || _stopping) return;
      unawaited(_stopRecording());
    });
  }

  List<PitchFrame> _attachCents(List<PitchFrame> f, List<NoteSegment> ref) {
    return f.map((frame) {
      double? target;
      for (final seg in ref) {
        if (frame.time >= seg.start && frame.time <= seg.end) {
          target = seg.targetMidi;
          break;
        }
      }
      if (frame.midi == null || target == null) {
        return frame;
      }
      final cents = 1200 * (frame.midi! - target) / 12;
      return PitchFrame(time: frame.time, hz: frame.hz, midi: frame.midi, centsError: cents);
    }).toList();
  }

  Future<void> _playReference() async {
    final warmup = appState.selectedWarmup.value;
    final path = await synth.renderWarmup(warmup);
    await synth.playFile(path);
  }

  Future<void> _playTake() async {
    if (recordedPath == null) return;
    if (!await File(recordedPath!).exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Audio file not found at $recordedPath')));
      }
      return;
    }
    await _player.stop();
    await _player.setVolume(1.0);
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.play(DeviceFileSource(recordedPath!));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Record')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<WarmupDefinition>(
              valueListenable: appState.selectedWarmup,
              builder: (context, warmup, _) => Text('Selected: ${warmup.name}'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: recording ? null : _playReference,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play Reference'),
                ),
                ElevatedButton.icon(
                  onPressed: recording ? null : _startRecording,
                  icon: const Icon(Icons.fiber_manual_record),
                  label: const Text('Start Recording'),
                ),
                ElevatedButton.icon(
                  onPressed: recording && !_stopping ? _stopRecording : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
                ElevatedButton.icon(
                  onPressed: recordedPath != null ? _playTake : null,
                  icon: const Icon(Icons.play_circle_fill),
                  label: const Text('Play Take'),
                ),
                ElevatedButton.icon(
                  onPressed: recordedPath != null ? _saveTake : null,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Take'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (metrics != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  MetricCard(label: 'Score', value: metrics!.score),
                  MetricCard(label: 'Mean abs cents', value: metrics!.mean),
                  MetricCard(label: 'Within 20c', value: metrics!.within20),
                  MetricCard(label: 'Within 50c', value: metrics!.within50),
                ],
              ),
            const SizedBox(height: 12),
            Expanded(
              child: PitchGraph(
                frames: frames,
                reference: const [],
                playheadTime: playhead,
                showDots: false,
                windowSeconds: 3.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MetricsDisplay {
  final String score;
  final String mean;
  final String within20;
  final String within50;

  MetricsDisplay({required this.score, required this.mean, required this.within20, required this.within50});

  factory MetricsDisplay.fromMetrics(dynamic m) {
    return MetricsDisplay(
      score: m.score.toStringAsFixed(1),
      mean: m.meanAbsCents.toStringAsFixed(1),
      within20: '${m.pctWithin20.toStringAsFixed(1)}%',
      within50: '${m.pctWithin50.toStringAsFixed(1)}%',
    );
  }
}
