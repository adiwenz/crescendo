import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../models/hold_exercise_result.dart';
import '../../models/metrics.dart';
import '../../models/pitch_frame.dart';
import '../../models/take.dart';
import '../../services/hold_exercise_controller.dart';
import '../../services/hold_exercise_repository.dart';
import '../../services/loudness_meter.dart';
import '../../services/storage/take_repository.dart';
import '../state.dart';
import '../../audio/wav_writer.dart';

class HoldExerciseScreen extends StatefulWidget {
  const HoldExerciseScreen({super.key});

  @override
  State<HoldExerciseScreen> createState() => _HoldExerciseScreenState();
}

class _HoldExerciseScreenState extends State<HoldExerciseScreen> {
  static const double _requiredHoldSec = 3.0;
  static const double _defaultTolerance = 30;
  static const List<int> _targetMidi = [57, 60, 62]; // A3, C4, D4

  final AudioRecorder _recorder = AudioRecorder();
  late HoldExerciseController _controller;
  late final HoldExerciseRepository _repo;
  late final TakeRepository _takeRepo;
  final _appState = AppState();
  final _player = AudioPlayer();

  double _targetHz = 440 / math.pow(2, 9 / 12); // default A3
  HoldExerciseState _state = const HoldExerciseState(
    targetHz: 0,
    toleranceCents: _defaultTolerance,
    onPitchSeconds: 0,
    progress: 0,
    centsError: null,
    rms: 0,
    success: false,
  );
  bool _running = false;
  StreamSubscription<Uint8List>? _pcmSub;
  final _samples = <double>[];
  double _timeCursor = 0.0;
  final _frames = <PitchFrame>[];

  @override
  void initState() {
    super.initState();
    _repo = HoldExerciseRepository();
    _takeRepo = TakeRepository();
    _resetController();
  }

  void _resetController() {
    _controller = HoldExerciseController(
      targetHz: _targetHz,
      toleranceCents: _defaultTolerance,
      requiredHoldSec: _requiredHoldSec,
      loudness: LoudnessMeter(windowSize: 2048, alpha: 0.2),
      onState: (s) => setState(() => _state = s),
    );
    _state = _state.copyWith(
      targetHz: _targetHz,
      toleranceCents: _defaultTolerance,
      onPitchSeconds: 0,
      progress: 0,
      success: false,
      centsError: null,
      rms: 0,
    );
  }

  @override
  void dispose() {
    _pcmSub?.cancel();
    _stopRecording();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mic permission required')));
      }
      return;
    }
    _frames.clear();
    _samples.clear();
    _timeCursor = 0;
    setState(() {
      _running = true;
      _state = _state.copyWith(onPitchSeconds: 0, progress: 0, success: false);
    });
    _resetController();
    _controller.start();
    await _playTargetTone();
    _pcmSub?.cancel();
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
        numChannels: 1,
      ),
    );
    _pcmSub = stream.listen((data) async {
      final buf = _pcm16BytesToDoubles(data);
      _samples.addAll(buf);
      final dt = buf.isEmpty ? 0.0 : buf.length / 44100;
      _timeCursor += dt;
      final pf = PitchFrame(time: _timeCursor);
      _frames.add(pf);
      double? rms;
      try {
        final amp = await _recorder.getAmplitude();
        final db = amp.current;
        if (db != null && db.isFinite) {
          rms = math.pow(10, db / 20).toDouble().clamp(0.0, 1.0);
        }
      } catch (_) {}
      _controller.addFrame(pf, rawBuffer: buf, rmsOverride: rms);
      if (_state.success) {
        _onSuccess();
      }
    });
  }

  Future<void> _stopRecording() async {
    await _pcmSub?.cancel();
    _pcmSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    setState(() => _running = false);
  }

  Future<void> _onSuccess() async {
    await _stopRecording();
    final elapsed = _state.onPitchSeconds;
    final double avgCents = _frames.isNotEmpty
        ? _frames
                .where((f) => f.hz != null && f.hz! > 0)
                .map((f) => 1200 * (math.log(f.hz! / _targetHz) / math.ln2))
                .fold<double>(0, (a, b) => a + b) /
            _frames.length
        : 0.0;
    await _repo.add(HoldExerciseResult(
      timestamp: DateTime.now(),
      targetHz: _targetHz,
      toleranceCents: _defaultTolerance,
      success: true,
      timeToSuccessSec: elapsed,
      avgCentsError: avgCents,
      avgRms: _state.rms,
    ));
    final take = Take(
      name: 'Hold ${_hzLabel(_targetHz)} ${DateTime.now().toIso8601String()}',
      createdAt: DateTime.now(),
      warmupId: 'hold',
      warmupName: 'Hold Exercise',
      audioPath: '',
      frames: List<PitchFrame>.from(_frames),
      metrics: Metrics(
        score: (_state.progress * 100).clamp(0, 100),
        meanAbsCents: avgCents.abs(),
        pctWithin20: 0,
        pctWithin50: 0,
        validFrames: _frames.length,
      ),
    );
    await _takeRepo.insert(take);
    _appState.takesVersion.value++;
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Hold complete!')));
    }
  }

  Future<void> _playTargetTone() async {
    final sr = 44100;
    final dur = 1.0;
    final samples = <int>[];
    for (var i = 0; i < sr * dur; i++) {
      final v = 0.2 * math.sin(2 * math.pi * _targetHz * i / sr);
      samples.add((v.clamp(-1.0, 1.0) * 32767).round());
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/hold_tone_${_targetHz.toStringAsFixed(1)}.wav';
    await WavWriter.writePcm16Mono(
        samples: samples, sampleRate: sr, path: path);
    await _player.stop();
    await _player.play(DeviceFileSource(path), volume: 0.5);
  }

  List<double> _pcm16BytesToDoubles(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    final out = <double>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final v = bd.getInt16(i, Endian.little);
      out.add(v / 32768.0);
    }
    return out;
  }

  void _pickTarget() {
    final midi = (List<int>.from(_targetMidi)..shuffle()).first;
    _targetHz = 440.0 * math.pow(2, (midi - 69) / 12.0);
    _resetController();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final on = _state.centsError != null &&
        _state.centsError!.abs() <= _defaultTolerance;
    final pct = (_state.progress * 100).clamp(0, 100).toStringAsFixed(0);
    return Scaffold(
      appBar: AppBar(title: const Text('Hold Exercise')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('Target: ${_hzLabel(_targetHz)}',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Tolerance: ±$_defaultTolerance cents'),
            const SizedBox(height: 12),
            _ProgressRing(progress: _state.progress),
            const SizedBox(height: 8),
            Text(
                'Hold ${_requiredHoldSec.toStringAsFixed(1)}s • Progress: $pct%'),
            const SizedBox(height: 16),
            _BreathBall(rms: _state.rms),
            const SizedBox(height: 16),
            _OnPitchIndicator(cents: _state.centsError, on: on),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _running ? null : _pickTarget,
                  child: const Text('Pick target'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _running ? null : _start,
                  child: const Text('Start'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _running ? _stopRecording : null,
                  child: const Text('Stop'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  final double progress;
  const _ProgressRing({required this.progress});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 10,
            backgroundColor: Colors.grey.shade200,
          ),
          Text('${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%'),
        ],
      ),
    );
  }
}

class _BreathBall extends StatelessWidget {
  final double rms;
  const _BreathBall({required this.rms});

  @override
  Widget build(BuildContext context) {
    final brightness = (rms * 8).clamp(0.0, 1.0);
    final color = Colors.blueAccent.withOpacity(0.3 + 0.7 * brightness);
    final label = rms < 0.02 ? 'Sing louder' : 'Breath steady';
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 80 + 20 * brightness,
          height: 80 + 20 * brightness,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color,
                Colors.blue.shade100.withOpacity(0.2 + 0.3 * brightness),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.6),
                blurRadius: 24 * brightness,
                spreadRadius: 6 * brightness,
              )
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _OnPitchIndicator extends StatelessWidget {
  final double? cents;
  final bool on;

  const _OnPitchIndicator({required this.cents, required this.on});

  @override
  Widget build(BuildContext context) {
    final color = on ? Colors.green : Colors.redAccent;
    final text = cents != null
        ? '${cents! >= 0 ? '+' : ''}${cents!.toStringAsFixed(0)} cents'
        : '—';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text('On pitch: ${on ? "Yes" : "No"} ($text)'),
      ],
    );
  }
}

String _hzLabel(double hz) {
  final midi = 69 + 12 * (math.log(hz / 440.0) / math.ln2);
  final rounded = midi.round();
  const names = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B'
  ];
  final name = names[rounded % 12];
  final octave = (rounded ~/ 12) - 1;
  return '$name$octave (${hz.toStringAsFixed(1)} Hz)';
}
