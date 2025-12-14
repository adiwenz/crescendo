import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/exercise_note.dart';
import '../../models/exercise_plan.dart';
import '../../models/reference_note.dart';
import '../../models/pitch_frame.dart';
import '../../models/take.dart';
import '../../services/pitch_detection_service.dart';
import '../../services/audio_synth_service.dart';
import '../../services/exercise_scoring_service.dart';
import '../../services/recording_service.dart';
import '../../services/scoring_service.dart';
import '../../services/storage/take_repository.dart';
import '../state.dart';
import '../widgets/staff_exercise_view.dart';
import 'package:audioplayers/audioplayers.dart';

class ExercisePitchScreen extends StatefulWidget {
  const ExercisePitchScreen({super.key});

  @override
  State<ExercisePitchScreen> createState() => _ExercisePitchScreenState();
}

class _ExercisePitchScreenState extends State<ExercisePitchScreen> with SingleTickerProviderStateMixin {
  late final ExercisePlan plan;
  late final PitchDetectionService _pitchService;
  late final AudioSynthService _synth;
  late final ExerciseScoringService _scoring;
  late final RecordingService _recording;
  late final ScoringService _metricsScoring;
  late final TakeRepository _repo;
  final appState = AppState();
  final AudioPlayer _player = AudioPlayer();

  late final Ticker _ticker;
  Duration? _lastTick;
  bool _running = false;
  double _elapsed = 0;
  bool _stopping = false;

  StreamSubscription? _pitchSub;
  StreamSubscription<PitchFrame>? _liveSub;
  StreamSubscription<void>? _referenceSub;
  final ValueNotifier<double?> _pitchMidi = ValueNotifier<double?>(null);
  final ValueNotifier<int> _currentIndex = ValueNotifier<int>(0);
  late List<ExerciseNoteScore> _scores;
  final List<PitchFrame> _capturedFrames = [];
  String? _recordedPath;

  @override
  void initState() {
    super.initState();
    plan = ExercisePlan(
      title: 'Scale',
      keyLabel: 'C Major',
      bpm: 120,
      gapSec: 0.1,
      notes: [
        for (final midi in [60, 62, 64, 65, 67, 69, 71, 72]) ExerciseNote(midi: midi, durationSec: 0.5),
      ],
    );
    _pitchService = PitchDetectionService();
    _synth = AudioSynthService();
    _scoring = ExerciseScoringService();
    _recording = RecordingService();
    _metricsScoring = ScoringService();
    _repo = TakeRepository();
    _scores = _scoring.emptyScores(plan.notes.length);
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pitchSub?.cancel();
    _liveSub?.cancel();
    _referenceSub?.cancel();
    _pitchService.stopStream();
    _recording.stop();
    _synth.stop();
    _player.dispose();
    _pitchMidi.dispose();
    _currentIndex.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_running) return;
    final dt = elapsed - (_lastTick ?? elapsed);
    _lastTick = elapsed;
    _advance(dt.inMicroseconds / 1e6);
  }

  void _advance(double delta) {
    _elapsed += delta;
    final idx = _noteIndexAt(_elapsed);
    if (idx != _currentIndex.value && idx < plan.notes.length) {
      _currentIndex.value = idx;
    }
    _collectPitch(idx);
    if (_elapsed >= _totalDuration) {
      _finishExercise();
    }
    setState(() {}); // throttled by ticker, not audio frames
  }

  double get _totalDuration {
    double t = 0;
    for (final n in plan.notes) {
      t += n.durationSec + plan.gapSec;
    }
    return t;
  }

  int _noteIndexAt(double t) {
    double cursor = 0;
    for (var i = 0; i < plan.notes.length; i++) {
      final start = cursor;
      final end = cursor + plan.notes[i].durationSec;
      if (t >= start && t < end) return i;
      cursor = end + plan.gapSec;
    }
    return plan.notes.length;
  }

  Future<void> _toggleRun() async {
    if (_running) {
      await _stop();
      return;
    }
    _resetScores();
    _running = true;
    _elapsed = 0;
    _recordedPath = null;
    _capturedFrames.clear();
    _lastTick = null;
    _ticker.start();
    await _startExercise();
  }

  Future<void> _startPitch() async {
    await _pitchSub?.cancel();
    final stream = await _pitchService.startStream();
    _pitchSub = stream.listen((pf) {
      final midi = pf.midi ?? (pf.hz != null ? _hzToMidi(pf.hz!) : null);
      _pitchMidi.value = midi;
    });
  }

  Future<void> _stop() async {
    if (_stopping) return;
    _stopping = true;
    _running = false;
    _ticker.stop();
    _lastTick = null;
    _referenceSub?.cancel();
    await _synth.stop();
    await _pitchSub?.cancel();
    await _pitchService.stopStream();
    await _liveSub?.cancel();
    final result = await _recording.stop();
    if (result.audioPath.isNotEmpty) {
      _recordedPath = result.audioPath;
      _capturedFrames.addAll(result.frames);
    }
    _stopping = false;
    setState(() {});
  }

  void _finishExercise() {
    _running = false;
    _ticker.stop();
    _lastTick = null;
    _pitchSub?.cancel();
    setState(() {});
  }

  void _collectPitch(int idx) {
    if (idx >= plan.notes.length) return;
    final midi = _pitchMidi.value;
    if (midi == null) return;
    final diff = midi - plan.notes[idx].midi;
    final cents = diff * 100;
    final score = _scores[idx];
    if (cents.abs() <= 25) {
      score.on++;
    } else if (cents.abs() <= 60) {
      score.near++;
    } else {
      score.off++;
    }
  }

  void _resetScores() {
    _scores = _scoring.emptyScores(plan.notes.length);
    _currentIndex.value = 0;
  }

  double _overallScore() {
    if (_scores.isEmpty) return 0;
    final avg = _scores.map((s) => s.onPct).fold(0.0, (a, b) => a + b) / _scores.length;
    return avg;
  }

  Future<void> _playReference() async {
    final refs = <ReferenceNote>[];
    double cursor = 0;
    for (final n in plan.notes) {
      refs.add(ReferenceNote(startSec: cursor, endSec: cursor + n.durationSec, midi: n.midi, lyric: n.solfege));
      cursor += n.durationSec + plan.gapSec;
    }
    final path = await _synth.renderReferenceNotes(refs);
    await _synth.playFile(path);
  }

  Future<void> _startExercise() async {
    await _startPitch();
    await _liveSub?.cancel();
    await _recording.start();
    _liveSub = _recording.liveStream.listen((frame) {
      final midi = frame.midi ?? (frame.hz != null ? _hzToMidi(frame.hz!) : null);
      if (midi == null) return;
      _pitchMidi.value = midi;
      _capturedFrames.add(PitchFrame(time: _elapsed, hz: frame.hz, midi: midi));
      _collectPitch(_currentIndex.value);
    });
    final refs = <ReferenceNote>[];
    double cursor = 0;
    for (final n in plan.notes) {
      refs.add(ReferenceNote(startSec: cursor, endSec: cursor + n.durationSec, midi: n.midi, lyric: n.solfege));
      cursor += n.durationSec + plan.gapSec;
    }
    final path = await _synth.renderReferenceNotes(refs);
    await _synth.stop();
    await _synth.playFile(path);
    _referenceSub?.cancel();
    _referenceSub = _synth.onComplete.listen((_) => _stop());
  }

  void _tryAgain() {
    _resetScores();
    _elapsed = 0;
    _pitchMidi.value = null;
    setState(() {});
  }

  Future<void> _playRecording() async {
    if (_recordedPath == null) return;
    await _player.stop();
    await _player.setVolume(1.0);
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.play(DeviceFileSource(_recordedPath!));
  }

  ReferenceNote? _noteAt(double t) {
    double cursor = 0;
    for (final n in plan.notes) {
      final start = cursor;
      final end = cursor + n.durationSec;
      if (t >= start && t <= end) return ReferenceNote(startSec: start, endSec: end, midi: n.midi, lyric: n.solfege);
      cursor = end + plan.gapSec;
    }
    return null;
  }

  List<PitchFrame> _attachCents(List<PitchFrame> frames) {
    return frames.map((f) {
      final note = _noteAt(f.time);
      if (note == null || f.midi == null) return f;
      final cents = (f.midi! - note.midi) * 100;
      return PitchFrame(time: f.time, hz: f.hz, midi: f.midi, centsError: cents);
    }).toList();
  }

  Future<void> _saveExercise() async {
    if (_recordedPath == null || _capturedFrames.isEmpty) return;
    final cleanFrames = _attachCents(_capturedFrames);
    final metrics = _metricsScoring.score(cleanFrames);
    final take = Take(
      name: 'Exercise ${plan.title} ${DateTime.now().toLocal()}',
      createdAt: DateTime.now(),
      warmupId: 'exercise_${plan.title.toLowerCase()}',
      warmupName: '${plan.keyLabel} ${plan.title}',
      audioPath: _recordedPath!,
      frames: cleanFrames,
      metrics: metrics,
    );
    await _repo.insert(take);
    appState.takesVersion.value++;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved exercise to history')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColors = _scores
        .map((s) => switch (s.rating) {
              NoteRating.good => Colors.green,
              NoteRating.near => Colors.orange,
              NoteRating.off => Colors.red,
            })
        .toList();
    return Scaffold(
      backgroundColor: Colors.blueGrey.shade50,
      appBar: AppBar(
        title: const Text('Exercise'),
        backgroundColor: Colors.blueGrey.shade50,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${plan.keyLabel} — ${plan.title}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Container(
                      height: 60,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Text('Pitch trace (live)', style: TextStyle(color: Colors.grey.shade600)),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: StaffExerciseView(
                          notes: plan.notes,
                          currentIndex: _currentIndex,
                          pitchMidi: _pitchMidi,
                          statuses: List.generate(plan.notes.length, (i) {
                            if (i < _scores.length && !_running && _elapsed >= _totalDuration) {
                              return _noteStatus(_scores[i]);
                            }
                            if (i < _scores.length && i < _noteIndexAt(_elapsed)) {
                              return _noteStatus(_scores[i]);
                            }
                            return NoteStatus.pending;
                          }),
                          midiCenter: 64,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text('Note ${math.min(_currentIndex.value + 1, plan.notes.length)} of ${plan.notes.length}'),
                        const SizedBox(width: 12),
                        Wrap(
                          spacing: 6,
                          children: [
                            for (var i = 0; i < plan.notes.length; i++)
                              Icon(Icons.circle,
                                  size: 10, color: i < statusColors.length ? statusColors[i] : Colors.grey.shade300),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!_running && _elapsed >= _totalDuration)
                      Text('Overall score: ${_overallScore().toStringAsFixed(1)}% on-pitch',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _playReference,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Play reference'),
                        ),
                        ElevatedButton.icon(
                          onPressed: _recordedPath != null ? _playRecording : null,
                          icon: const Icon(Icons.play_circle_fill),
                          label: const Text('Replay exercise'),
                        ),
                        ElevatedButton.icon(
                          onPressed: _toggleRun,
                          icon: Icon(_running ? Icons.stop : Icons.mic),
                          label: Text(_running ? 'Stop' : 'Start'),
                        ),
                        ElevatedButton.icon(
                          onPressed: _tryAgain,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try again'),
                        ),
                        ElevatedButton.icon(
                          onPressed: _recordedPath != null ? _saveExercise : null,
                          icon: const Icon(Icons.save),
                          label: const Text('Save to history'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  NoteStatus _noteStatus(ExerciseNoteScore s) {
    return switch (s.rating) {
      NoteRating.good => NoteStatus.good,
      NoteRating.near => NoteStatus.near,
      NoteRating.off => NoteStatus.off,
    };
  }

  double _hzToMidi(double hz) => 69 + 12 * math.log(hz / 440) / math.ln2;
}
