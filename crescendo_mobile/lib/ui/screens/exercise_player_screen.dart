import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/pitch_frame.dart';
import '../../models/reference_note.dart';
import '../../models/vocal_exercise.dart';
import '../../services/audio_synth_service.dart';
import '../../services/recording_service.dart';
import '../widgets/pitch_highway_painter.dart';

class ExercisePlayerScreen extends StatelessWidget {
  final VocalExercise exercise;

  const ExercisePlayerScreen({super.key, required this.exercise});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(exercise.name)),
      body: switch (exercise.type) {
        ExerciseType.pitchHighway => PitchHighwayPlayer(exercise: exercise),
        ExerciseType.breathTimer => BreathTimerPlayer(exercise: exercise),
        ExerciseType.sovtTimer => SovtTimerPlayer(exercise: exercise),
        ExerciseType.sustainedPitchHold => SustainedPitchHoldPlayer(exercise: exercise),
        ExerciseType.pitchMatchListening => PitchMatchListeningPlayer(exercise: exercise),
        ExerciseType.articulationRhythm => ArticulationRhythmPlayer(exercise: exercise),
        ExerciseType.dynamicsRamp => DynamicsRampPlayer(exercise: exercise),
        ExerciseType.cooldownRecovery => CooldownRecoveryPlayer(exercise: exercise),
      },
    );
  }
}

class PitchHighwayPlayer extends StatefulWidget {
  final VocalExercise exercise;

  const PitchHighwayPlayer({super.key, required this.exercise});

  @override
  State<PitchHighwayPlayer> createState() => _PitchHighwayPlayerState();
}

class _PitchHighwayPlayerState extends State<PitchHighwayPlayer>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  final List<PitchFrame> _tail = [];
  final _tailWindowSec = 4.0;
  Ticker? _ticker;
  Duration? _lastTick;
  bool _playing = false;
  bool _useMic = true;
  int _transpose = 0;
  RecordingService? _recording;
  StreamSubscription<PitchFrame>? _sub;

  double get _durationSec =>
      (widget.exercise.highwaySpec?.totalMs ?? 0) / 1000.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _sub?.cancel();
    _recording?.stop();
    _time.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_playing) return;
    final dt = elapsed - (_lastTick ?? elapsed);
    _lastTick = elapsed;
    final next = _time.value + dt.inMicroseconds / 1e6;
    _time.value = next;
    _trimTail();
    if (!_useMic) {
      _simulatePitch(next);
    }
    if (next >= _durationSec) {
      _stop();
    }
  }

  void _trimTail() {
    final cutoff = _time.value - _tailWindowSec;
    final idx = _tail.indexWhere((f) => f.time >= cutoff);
    if (idx > 0) {
      _tail.removeRange(0, idx);
    } else if (idx == -1 && _tail.isNotEmpty) {
      _tail.clear();
    }
  }

  Future<void> _start() async {
    if (_playing) return;
    _tail.clear();
    _time.value = 0;
    _playing = true;
    _lastTick = null;
    _ticker?.start();
    if (_useMic) {
      _recording = RecordingService();
      await _recording?.start();
      _sub = _recording?.liveStream.listen((frame) {
        final midi = frame.midi ??
            (frame.hz != null ? 69 + 12 * math.log(frame.hz! / 440.0) / math.ln2 : null);
        if (midi == null) return;
        _tail.add(PitchFrame(
          time: _time.value,
          hz: frame.hz,
          midi: midi,
          voicedProb: frame.voicedProb,
          rms: frame.rms,
        ));
        _trimTail();
      });
    }
    setState(() {});
  }

  Future<void> _stop() async {
    if (!_playing) return;
    _playing = false;
    _ticker?.stop();
    _lastTick = null;
    await _sub?.cancel();
    _sub = null;
    await _recording?.stop();
    _recording = null;
    setState(() {});
  }

  void _simulatePitch(double t) {
    // TODO: Replace simulation with real pitch stream if mic is unavailable.
    final targetMidi = _targetMidiAtTime(t);
    if (targetMidi == null) return;
    final vibrato = math.sin(t * 2 * math.pi * 5) * 0.2;
    final midi = targetMidi + vibrato;
    final hz = 440.0 * math.pow(2.0, (midi - 69) / 12.0);
    _tail.add(PitchFrame(time: t, hz: hz, midi: midi));
  }

  double? _targetMidiAtTime(double t) {
    final spec = widget.exercise.highwaySpec;
    if (spec == null) return null;
    final ms = (t * 1000).round();
    for (final seg in spec.segments) {
      if (ms < seg.startMs || ms > seg.endMs) continue;
      if (seg.isGlide) {
        final start = seg.startMidi ?? seg.midiNote;
        final end = seg.endMidi ?? seg.midiNote;
        final ratio = (ms - seg.startMs) / math.max(1, seg.endMs - seg.startMs);
        return (start + (end - start) * ratio) + _transpose;
      }
      return (seg.midiNote + _transpose).toDouble();
    }
    return null;
  }

  String? _labelAtTime(double t) {
    final spec = widget.exercise.highwaySpec;
    if (spec == null) return null;
    final ms = (t * 1000).round();
    for (final seg in spec.segments) {
      if (ms >= seg.startMs && ms <= seg.endMs) return seg.label;
    }
    return null;
  }

  List<ReferenceNote> _buildReferenceNotes() {
    final spec = widget.exercise.highwaySpec;
    if (spec == null) return const [];
    final notes = <ReferenceNote>[];
    for (final seg in spec.segments) {
      if (seg.isGlide) {
        final startMidi = seg.startMidi ?? seg.midiNote;
        final endMidi = seg.endMidi ?? seg.midiNote;
        final durationMs = seg.endMs - seg.startMs;
        final steps = math.max(4, (durationMs / 200).round());
        for (var i = 0; i < steps; i++) {
          final ratio = i / steps;
          final midi = (startMidi + (endMidi - startMidi) * ratio).round();
          final stepStart = seg.startMs + (durationMs * ratio).round();
          final stepEnd = seg.startMs + (durationMs * ((i + 1) / steps)).round();
          notes.add(ReferenceNote(
            startSec: stepStart / 1000.0,
            endSec: stepEnd / 1000.0,
            midi: midi + _transpose,
            lyric: seg.label,
          ));
        }
      } else {
        notes.add(ReferenceNote(
          startSec: seg.startMs / 1000.0,
          endSec: seg.endMs / 1000.0,
          midi: seg.midiNote + _transpose,
          lyric: seg.label,
        ));
      }
    }
    return notes;
  }

  @override
  Widget build(BuildContext context) {
    final notes = _buildReferenceNotes();
    final midiValues = notes.map((n) => n.midi).toList();
    final minMidi = midiValues.isNotEmpty ? (midiValues.reduce(math.min) - 4) : 48;
    final maxMidi = midiValues.isNotEmpty ? (midiValues.reduce(math.max) + 4) : 72;
    final label = _labelAtTime(_time.value);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.exercise.description, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          if (label != null) Text('Current syllable: $label'),
          const SizedBox(height: 8),
          SizedBox(
            height: 260,
            child: CustomPaint(
              painter: PitchHighwayPainter(
                notes: notes,
                pitchTail: _tail,
                time: _time,
                midiMin: minMidi,
                midiMax: maxMidi,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Transpose'),
              Expanded(
                child: Slider(
                  value: _transpose.toDouble(),
                  min: -12,
                  max: 12,
                  divisions: 24,
                  label: '${_transpose} st',
                  onChanged: (v) => setState(() => _transpose = v.round()),
                ),
              ),
            ],
          ),
          SwitchListTile(
            value: _useMic,
            onChanged: (v) async {
              if (_playing) {
                await _stop();
              }
              setState(() => _useMic = v);
            },
            title: const Text('Use microphone'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _playing ? _stop : _start,
            icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
            label: Text(_playing ? 'Stop' : 'Start'),
          ),
        ],
      ),
    );
  }
}

class BreathTimerPlayer extends StatefulWidget {
  final VocalExercise exercise;

  const BreathTimerPlayer({super.key, required this.exercise});

  @override
  State<BreathTimerPlayer> createState() => _BreathTimerPlayerState();
}

class _BreathTimerPlayerState extends State<BreathTimerPlayer>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration? _lastTick;
  bool _running = false;
  double _elapsed = 0;
  final _phases = const [
    _BreathPhase('Inhale', 4),
    _BreathPhase('Hold', 4),
    _BreathPhase('Exhale', 6),
  ];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_running) return;
    final dt = elapsed - (_lastTick ?? elapsed);
    _lastTick = elapsed;
    setState(() => _elapsed += dt.inMicroseconds / 1e6);
  }

  @override
  Widget build(BuildContext context) {
    final total = _phases.fold<double>(0, (a, b) => a + b.durationSec);
    var remaining = _elapsed % total;
    _BreathPhase current = _phases.first;
    for (final phase in _phases) {
      if (remaining <= phase.durationSec) {
        current = phase;
        break;
      }
      remaining -= phase.durationSec;
    }
    final phaseProgress = remaining / current.durationSec;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.exercise.description),
          const SizedBox(height: 16),
          Text(current.label, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: phaseProgress),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _running = !_running;
                if (_running) {
                  _lastTick = null;
                  _ticker?.start();
                } else {
                  _ticker?.stop();
                }
              });
            },
            icon: Icon(_running ? Icons.stop : Icons.play_arrow),
            label: Text(_running ? 'Stop' : 'Start'),
          ),
        ],
      ),
    );
  }
}

class SovtTimerPlayer extends StatefulWidget {
  final VocalExercise exercise;

  const SovtTimerPlayer({super.key, required this.exercise});

  @override
  State<SovtTimerPlayer> createState() => _SovtTimerPlayerState();
}

class _SovtTimerPlayerState extends State<SovtTimerPlayer>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration? _lastTick;
  bool _running = false;
  double _elapsed = 0;
  bool _phonationOn = true;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_running) return;
    final dt = elapsed - (_lastTick ?? elapsed);
    _lastTick = elapsed;
    setState(() => _elapsed += dt.inMicroseconds / 1e6);
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.exercise.durationSeconds ?? 120;
    final remaining = math.max(0, duration - _elapsed);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.exercise.description),
          const SizedBox(height: 16),
          Text('${remaining.toStringAsFixed(0)}s remaining',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Phonation on/off'),
            value: _phonationOn,
            onChanged: (v) => setState(() => _phonationOn = v),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _running = !_running;
                if (_running) {
                  _lastTick = null;
                  _ticker?.start();
                } else {
                  _ticker?.stop();
                }
              });
            },
            icon: Icon(_running ? Icons.stop : Icons.play_arrow),
            label: Text(_running ? 'Stop' : 'Start'),
          ),
        ],
      ),
    );
  }
}

class SustainedPitchHoldPlayer extends StatefulWidget {
  final VocalExercise exercise;

  const SustainedPitchHoldPlayer({super.key, required this.exercise});

  @override
  State<SustainedPitchHoldPlayer> createState() => _SustainedPitchHoldPlayerState();
}

class _SustainedPitchHoldPlayerState extends State<SustainedPitchHoldPlayer> {
  final _recording = RecordingService();
  StreamSubscription<PitchFrame>? _sub;
  bool _listening = false;
  int _targetMidi = 60;
  double _centsError = 0;
  double _onPitchSec = 0;
  double _listeningSec = 0;
  double _lastTime = 0;
  final _holdGoalSec = 3.0;

  @override
  void dispose() {
    _sub?.cancel();
    _recording.stop();
    super.dispose();
  }

  double get _targetHz => 440.0 * math.pow(2.0, (_targetMidi - 69) / 12.0);

  Future<void> _toggle() async {
    if (_listening) {
      await _sub?.cancel();
      await _recording.stop();
      setState(() => _listening = false);
      return;
    }
    await _recording.start();
    _lastTime = 0;
    _onPitchSec = 0;
    _listeningSec = 0;
    _sub = _recording.liveStream.listen((frame) {
      final hz = frame.hz;
      if (hz == null || hz <= 0) return;
      final cents = 1200 * (math.log(hz / _targetHz) / math.ln2);
      final dt = _lastTime == 0 ? 0 : math.max(0, frame.time - _lastTime);
      _lastTime = frame.time;
      if (dt > 0) {
        _listeningSec += dt;
      }
      final voiced = (frame.voicedProb ?? 1.0) >= 0.6 && (frame.rms ?? 1.0) >= 0.02;
      if (voiced && cents.abs() <= 25) {
        _onPitchSec += dt;
      } else if (dt > 0.2) {
        _onPitchSec = 0;
      }
      setState(() => _centsError = cents);
    });
    setState(() => _listening = true);
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_onPitchSec / _holdGoalSec).clamp(0.0, 1.0);
    final stability = _listeningSec > 0 ? (_onPitchSec / _listeningSec) : 0.0;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.exercise.description),
          const SizedBox(height: 12),
          Text('Target: MIDI $_targetMidi', style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: _targetMidi.toDouble(),
            min: 48,
            max: 72,
            divisions: 24,
            label: _targetMidi.toString(),
            onChanged: (v) => setState(() => _targetMidi = v.round()),
          ),
          const SizedBox(height: 8),
          Text('${_centsError.toStringAsFixed(1)} cents',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          Text('Stability: ${(stability * 100).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _toggle,
            icon: Icon(_listening ? Icons.stop : Icons.hearing),
            label: Text(_listening ? 'Stop' : 'Listen'),
          ),
        ],
      ),
    );
  }
}

class PitchMatchListeningPlayer extends StatefulWidget {
  final VocalExercise exercise;

  const PitchMatchListeningPlayer({super.key, required this.exercise});

  @override
  State<PitchMatchListeningPlayer> createState() => _PitchMatchListeningPlayerState();
}

class _PitchMatchListeningPlayerState extends State<PitchMatchListeningPlayer> {
  final _synth = AudioSynthService();
  final _recording = RecordingService();
  StreamSubscription<PitchFrame>? _sub;
  bool _listening = false;
  int _targetMidi = 60;
  double _centsError = 0;

  @override
  void dispose() {
    _sub?.cancel();
    _recording.stop();
    _synth.stop();
    super.dispose();
  }

  double get _targetHz => 440.0 * math.pow(2.0, (_targetMidi - 69) / 12.0);

  Future<void> _playTone() async {
    final notes = [
      ReferenceNote(startSec: 0, endSec: 1.2, midi: _targetMidi),
    ];
    final path = await _synth.renderReferenceNotes(notes);
    await _synth.playFile(path);
  }

  Future<void> _toggleListen() async {
    if (_listening) {
      await _sub?.cancel();
      await _recording.stop();
      setState(() => _listening = false);
      return;
    }
    await _recording.start();
    _sub = _recording.liveStream.listen((frame) {
      final hz = frame.hz;
      if (hz == null || hz <= 0) return;
      final cents = 1200 * (math.log(hz / _targetHz) / math.ln2);
      setState(() => _centsError = cents);
    });
    setState(() => _listening = true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.exercise.description),
          const SizedBox(height: 12),
          Text('Target: MIDI $_targetMidi', style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: _targetMidi.toDouble(),
            min: 48,
            max: 72,
            divisions: 24,
            label: _targetMidi.toString(),
            onChanged: (v) => setState(() => _targetMidi = v.round()),
          ),
          const SizedBox(height: 8),
          Text('${_centsError.toStringAsFixed(1)} cents',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _playTone,
                  icon: const Icon(Icons.volume_up),
                  label: const Text('Play tone'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _toggleListen,
                  icon: Icon(_listening ? Icons.stop : Icons.hearing),
                  label: Text(_listening ? 'Stop' : 'Listen'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ArticulationRhythmPlayer extends StatefulWidget {
  final VocalExercise exercise;

  const ArticulationRhythmPlayer({super.key, required this.exercise});

  @override
  State<ArticulationRhythmPlayer> createState() => _ArticulationRhythmPlayerState();
}

class _ArticulationRhythmPlayerState extends State<ArticulationRhythmPlayer>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration? _lastTick;
  bool _running = false;
  double _elapsed = 0;
  final _tempoBpm = 90.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_running) return;
    final dt = elapsed - (_lastTick ?? elapsed);
    _lastTick = elapsed;
    setState(() => _elapsed += dt.inMicroseconds / 1e6);
  }

  List<String> get _syllables {
    if (widget.exercise.id == 'tongue_twisters') {
      return const ['Red', 'leather', 'yellow', 'leather'];
    }
    if (widget.exercise.id == 'consonant_isolation') {
      return const ['T', 'K', 'D', 'T', 'K', 'D'];
    }
    return const ['Ta', 'Ta', 'Ta', 'Ta'];
  }

  @override
  Widget build(BuildContext context) {
    final beatSec = 60 / _tempoBpm;
    final beatIndex = ((_elapsed / beatSec).floor()) % _syllables.length;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.exercise.description),
          const SizedBox(height: 16),
          Text('Tempo: ${_tempoBpm.toStringAsFixed(0)} bpm'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: List.generate(_syllables.length, (i) {
              final active = i == beatIndex && _running;
              return Chip(
                label: Text(_syllables[i]),
                backgroundColor: active ? Colors.blue.shade200 : Colors.grey.shade200,
              );
            }),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _running = !_running;
                if (_running) {
                  _lastTick = null;
                  _ticker?.start();
                } else {
                  _ticker?.stop();
                }
              });
            },
            icon: Icon(_running ? Icons.stop : Icons.play_arrow),
            label: Text(_running ? 'Stop' : 'Start'),
          ),
        ],
      ),
    );
  }
}

class DynamicsRampPlayer extends StatefulWidget {
  final VocalExercise exercise;

  const DynamicsRampPlayer({super.key, required this.exercise});

  @override
  State<DynamicsRampPlayer> createState() => _DynamicsRampPlayerState();
}

class _DynamicsRampPlayerState extends State<DynamicsRampPlayer>
    with SingleTickerProviderStateMixin {
  final _recording = RecordingService();
  StreamSubscription<PitchFrame>? _sub;
  Ticker? _ticker;
  Duration? _lastTick;
  bool _running = false;
  double _elapsed = 0;
  double _rms = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _sub?.cancel();
    _recording.stop();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_running) return;
    final dt = elapsed - (_lastTick ?? elapsed);
    _lastTick = elapsed;
    setState(() => _elapsed += dt.inMicroseconds / 1e6);
  }

  Future<void> _toggle() async {
    if (_running) {
      _ticker?.stop();
      await _sub?.cancel();
      await _recording.stop();
      setState(() => _running = false);
      return;
    }
    await _recording.start();
    _sub = _recording.liveStream.listen((frame) {
      setState(() => _rms = frame.rms ?? 0.0);
    });
    setState(() {
      _running = true;
      _elapsed = 0;
      _lastTick = null;
      _ticker?.start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.exercise.durationSeconds ?? 120;
    final progress = (_elapsed / duration).clamp(0.0, 1.0);
    final ramp = progress <= 0.5 ? (progress * 2) : (1 - (progress - 0.5) * 2);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.exercise.description),
          const SizedBox(height: 16),
          Text('Target ramp'),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: ramp),
          const SizedBox(height: 16),
          Text('Current loudness'),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: _rms.clamp(0.0, 1.0)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _toggle,
            icon: Icon(_running ? Icons.stop : Icons.play_arrow),
            label: Text(_running ? 'Stop' : 'Start'),
          ),
        ],
      ),
    );
  }
}

class CooldownRecoveryPlayer extends StatefulWidget {
  final VocalExercise exercise;

  const CooldownRecoveryPlayer({super.key, required this.exercise});

  @override
  State<CooldownRecoveryPlayer> createState() => _CooldownRecoveryPlayerState();
}

class _CooldownRecoveryPlayerState extends State<CooldownRecoveryPlayer>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration? _lastTick;
  bool _running = false;
  double _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_running) return;
    final dt = elapsed - (_lastTick ?? elapsed);
    _lastTick = elapsed;
    setState(() => _elapsed += dt.inMicroseconds / 1e6);
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.exercise.durationSeconds ?? 90;
    final remaining = math.max(0, duration - _elapsed);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.exercise.description),
          const SizedBox(height: 16),
          Text('${remaining.toStringAsFixed(0)}s remaining',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _running = !_running;
                if (_running) {
                  _lastTick = null;
                  _ticker?.start();
                } else {
                  _ticker?.stop();
                }
              });
            },
            icon: Icon(_running ? Icons.stop : Icons.play_arrow),
            label: Text(_running ? 'Stop' : 'Start'),
          ),
        ],
      ),
    );
  }
}

class _BreathPhase {
  final String label;
  final double durationSec;

  const _BreathPhase(this.label, this.durationSec);
}
