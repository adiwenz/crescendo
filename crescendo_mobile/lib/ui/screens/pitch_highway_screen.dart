import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';

import '../../models/pitch_frame.dart';
import '../../models/reference_note.dart';
import '../../models/take.dart';
import '../../services/audio_synth_service.dart';
import '../../services/recording_service.dart';
import '../../services/scoring_service.dart';
import '../../services/storage/take_repository.dart';
import '../../services/audio_alignment_service.dart';
import '../../models/audio_sync_info.dart';
import '../state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/debug_overlay.dart';
import '../widgets/pitch_highway_painter.dart';
import '../../utils/pitch_math.dart';
import '../../utils/performance_clock.dart';
import '../../utils/pitch_ball_controller.dart';
import '../../utils/pitch_state.dart';
import '../../utils/pitch_visual_state.dart';
import '../../utils/pitch_tail_buffer.dart';

class PitchHighwayScreen extends StatefulWidget {
  const PitchHighwayScreen({super.key});

  @override
  State<PitchHighwayScreen> createState() => _PitchHighwayScreenState();
}

class _PitchHighwayScreenState extends State<PitchHighwayScreen> with SingleTickerProviderStateMixin {
  final pixelsPerSecond = 160.0;
  final playheadFraction = 0.45;
  final tailWindowSec = 4.0;
  final midiRange = const (min: 48, max: 72);
  final double _leadInSec = 2.0;

  final _timeNotifier = ValueNotifier<double>(0);
  final _liveMidi = ValueNotifier<double?>(null);
  final _capturedFrames = <PitchFrame>[];
  final PerformanceClock _clock = PerformanceClock();
  final PitchBallController _pitchBall = PitchBallController();
  final PitchState _pitchState = PitchState();
  final PitchVisualState _visualState = PitchVisualState();
  final PitchTailBuffer _tailBuffer = PitchTailBuffer();
  static const _showDebugOverlay =
      bool.fromEnvironment('SHOW_PITCH_DEBUG', defaultValue: false);

  late final Ticker _ticker;
  bool _playing = false;
  bool _recordingActive = false;
  bool _audioStarted = false;
  Size? _canvasSize;

  late final RecordingService _recording;
  StreamSubscription<PitchFrame>? _liveSub;
  StreamSubscription<Duration>? _audioPosSub;
  late final AudioSynthService _synth;
  late final ScoringService _scoring;
  late final TakeRepository _repo;
  final appState = AppState();
  String? _referencePath;
  String? _lastRecordingPath;
  double? _audioPositionSec;
  double _manualOffsetMs = 0;
  late final double _audioLatencyMs;
  final double _pitchInputLatencyMs = 25;
  AudioSyncInfo? _syncInfo;

  List<ReferenceNote> get _baseNotes => const [
        ReferenceNote(startSec: 0, endSec: 1.2, midi: 60, lyric: 'A'),
        ReferenceNote(startSec: 1.35, endSec: 2.4, midi: 62, lyric: 'new'),
        ReferenceNote(startSec: 2.5, endSec: 3.4, midi: 64, lyric: 'fan-'),
        ReferenceNote(startSec: 3.45, endSec: 4.4, midi: 65, lyric: 'tas-'),
        ReferenceNote(startSec: 4.6, endSec: 5.3, midi: 64, lyric: 'tic'),
        ReferenceNote(startSec: 5.5, endSec: 6.4, midi: 62, lyric: 'point'),
        ReferenceNote(startSec: 6.6, endSec: 7.2, midi: 60, lyric: 'of'),
        ReferenceNote(startSec: 7.35, endSec: 8.4, midi: 59, lyric: 'view'),
        ReferenceNote(startSec: 8.6, endSec: 9.6, midi: 60, lyric: 'yeah'),
      ];

  List<ReferenceNote> get _notesWithLeadIn => _baseNotes
      .map(
        (n) => ReferenceNote(
          startSec: n.startSec + _leadInSec,
          endSec: n.endSec + _leadInSec,
          midi: n.midi,
          lyric: n.lyric,
        ),
      )
      .toList();

  double get _totalDuration =>
      _notesWithLeadIn.map((n) => n.endSec).fold(0.0, math.max) +
      AudioSynthService.tailSeconds;

  @override
  void initState() {
    super.initState();
    _recording = RecordingService(bufferSize: 512);
    _synth = AudioSynthService();
    _scoring = ScoringService();
    _repo = TakeRepository();
    _ticker = createTicker(_onTick);
    _audioLatencyMs = kIsWeb ? 0 : (Platform.isIOS ? 150.0 : 200.0);
    _clock.setAudioPositionProvider(() => _audioPositionSec);
    _clock.setLatencyCompensationMs(_audioLatencyMs);
  }

  @override
  void dispose() {
    // ignore: avoid_print
    print('[PitchHighwayScreen] dispose - cleaning up resources');
    _ticker.dispose();
    _liveSub?.cancel();
    _audioPosSub?.cancel();
    // Properly stop and dispose the recording service
    _recording.stop().then((_) async {
      try {
        await _recording.dispose();
        // ignore: avoid_print
        print('[PitchHighwayScreen] Recording disposed');
      } catch (e) {
        // ignore: avoid_print
        print('[PitchHighwayScreen] Error disposing recording: $e');
      }
    }).catchError((e) {
      // ignore: avoid_print
      print('[PitchHighwayScreen] Error stopping recording: $e');
    });
    _synth.stop();
    _timeNotifier.dispose();
    _liveMidi.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_playing) return;
    final now = _clock.nowSeconds();
    final effectiveMidi = _pitchState.effectiveMidi;
    final effectiveHz = _pitchState.effectiveHz;
    _visualState.update(
      timeSec: now,
      pitchHz: effectiveHz,
      pitchMidi: effectiveMidi,
      voiced: _pitchState.isVoiced,
    );
    _timeNotifier.value = now;
    _liveMidi.value = _visualState.visualPitchMidi;
    final visualMidi = _visualState.visualPitchMidi;
    if (_canvasSize != null && visualMidi != null) {
      final y = PitchMath.midiToY(
        midi: visualMidi,
        height: _canvasSize!.height,
        midiMin: midiRange.min,
        midiMax: midiRange.max,
      );
      assert(y.isFinite);
      _tailBuffer.addPoint(tSec: now, yPx: y, voiced: _visualState.isVoiced);
      _tailBuffer.pruneOlderThan(now - tailWindowSec);
      assert(!_playing || _tailBuffer.points.isNotEmpty);
    }
    if (now > _totalDuration) {
      unawaited(_togglePlayback(force: false));
    }
  }

  Future<void> _togglePlayback({bool? force}) async {
    final target = force ?? !_playing;
    if (target == _playing) return;
    if (target) {
      if (_timeNotifier.value >= _totalDuration) {
        _timeNotifier.value = 0;
        _tailBuffer.clear();
        _capturedFrames.clear();
        _lastRecordingPath = null;
        _pitchBall.reset();
        _pitchState.reset();
        _visualState.reset();
      }
      _audioPositionSec = null;
      _audioStarted = false;
    _clock.setLatencyCompensationMs(_audioLatencyMs + _manualOffsetMs);
    _clock.start(offsetSec: _timeNotifier.value, freezeUntilAudio: true);
    _playing = true;
    _ticker.start();
    await _startRecording();
    
    // Give the recorder a moment to warm up so it captures the chirp at t=0
    await Future.delayed(const Duration(milliseconds: 200));
    
    await _playReference();
    } else {
      _playing = false;
      _ticker.stop();
      _clock.pause();
      await _stopRecording();
      await _synth.stop();
      await _audioPosSub?.cancel();
      _audioPosSub = null;
      _audioPositionSec = null;
      _liveMidi.value = null;
      _pitchState.reset();
      _visualState.reset();
      _tailBuffer.clear();
    }
    setState(() {});
  }

  Future<void> _startRecording() async {
    _capturedFrames.clear();
    await _liveSub?.cancel();
    await _recording.start(owner: 'exercise');
    _recordingActive = true;
    _liveSub = _recording.liveStream.listen((frame) {
      final midi = frame.midi ?? (frame.hz != null ? _hzToMidi(frame.hz!) : null);
      final now =
          (_clock.nowSeconds() - (_pitchInputLatencyMs / 1000.0)).clamp(-2.0, 3600.0);
      _handlePitchSample(
        time: now,
        hz: frame.hz,
        midi: midi,
        voicedProb: frame.voicedProb,
        rms: frame.rms,
      );
    });
  }

  Future<void> _stopRecording() async {
    if (!_recordingActive) return;
    _recordingActive = false;
    await _liveSub?.cancel();
    _liveSub = null;
    // ignore: avoid_print
    print('[PitchHighwayScreen] _stopRecording - stopping recording');
    final result = await _recording.stop();
    
    if (result != null) {
      // 1. Ensure WAV is ready
      final wavPath = await result.wavPathFuture;
      _lastRecordingPath = wavPath;
      
      // 2. Perform Ultrasonic Alignment
      if (_referencePath != null && _referencePath!.isNotEmpty) {
         try {
           final refBytes = await File(_referencePath!).readAsBytes();
           final recBytes = await File(wavPath).readAsBytes();
           
           final sync = await AudioAlignmentService.computeSync(
             refBytes: refBytes, 
             recBytes: recBytes
           );
           
           if (sync != null) {
              _syncInfo = sync;
              final offset = sync.timeOffsetSec;

              // NEW: Sample-Domain Alignment (Trim/Pad the File)
              final alignedPath = await AudioAlignmentService.alignAndSave(
                  recWav: File(wavPath),
                  sync: sync
              );
              _lastRecordingPath = alignedPath; // Use ALIGNED file for replay/review

              print('[ALIGN] refLag=${sync.refSyncSample} recLag=${sync.recordedSyncSample} offsetSamples=${sync.sampleOffset} offsetSec=${offset.toStringAsFixed(4)}');
              
              // 3. Correct timestamps (ALIGN METADATA TO AUDIO)
              // Since we shifted the audio to align with Ref t=0, 
              // we must shift the pitch frames similarly so they match the new audio.
              for (var i=0; i<_capturedFrames.length; i++) {
                 final f = _capturedFrames[i];
                 final newTime = math.max(0.0, f.time - offset);
                 _capturedFrames[i] = PitchFrame(
                   time: newTime,
                   hz: f.hz,
                   midi: f.midi,
                   voicedProb: f.voicedProb,
                   rms: f.rms,
                   centsError: f.centsError
                 );
              }
           } else {
              print('[PitchHighway] Sync failed (marker not found)');
              _syncInfo = null;
           }
         } catch (e) {
           print('[PitchHighway] Sync error: $e');
         }
      }
    }

    // Dispose the recording service to fully release resources
    try {
      await _recording.dispose();
      // ignore: avoid_print
      print('[PitchHighwayScreen] Recording disposed');
    } catch (e) {
      // ignore: avoid_print
      print('[PitchHighwayScreen] Error disposing recording: $e');
    }
  }

  Future<String> _ensureReferenceAudio() async {
    if (_referencePath != null) return _referencePath!;
    _referencePath = await _synth.renderReferenceNotes(_notesWithLeadIn);
    return _referencePath!;
  }

  Future<void> _playReference() async {
    final path = await _ensureReferenceAudio();
    await _synth.stop();
    await _synth.playFile(path);
    await _audioPosSub?.cancel();
    _audioPosSub = _synth.onPositionChanged.listen((pos) {
      if (!_audioStarted && pos > Duration.zero) {
        _audioStarted = true;
      }
      if (_audioStarted) {
        _audioPositionSec = pos.inMilliseconds / 1000.0;
      }
    });
  }

  ReferenceNote? _noteAt(double t) {
    for (final n in _notesWithLeadIn) {
      if (t >= n.startSec && t <= n.endSec) return n;
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

  Future<void> _saveTake() async {
    if (_lastRecordingPath == null || _capturedFrames.isEmpty) return;
    final cleanFrames = _attachCents(_capturedFrames);
    final metrics = _scoring.score(cleanFrames);
    final take = Take(
      name: 'Pitch Highway ${DateTime.now().toLocal()}',
      createdAt: DateTime.now(),
      warmupId: 'pitch_highway_stub',
      warmupName: 'Pitch Highway',
      audioPath: _lastRecordingPath!,
      frames: cleanFrames,
      metrics: metrics,
      syncInfo: _syncInfo,
    );
    await _repo.insert(take);
    appState.takesVersion.value++;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved take to history')));
    }
  }

  double _hzToMidi(double hz) => 69 + 12 * math.log(hz / 440) / math.ln2;

  void _handlePitchSample({
    required double time,
    required double? midi,
    double? hz,
    double? voicedProb,
    double? rms,
  }) {
    final voiced = midi != null && (voicedProb ?? 1.0) >= 0.6 && (rms ?? 1.0) >= 0.02;
    double? filtered;
    if (voiced) {
      _pitchBall.addSample(timeSec: time, midi: midi!);
      filtered = _pitchBall.lastSampleMidi ?? midi!;
      _pitchState.updateVoiced(timeSec: time, pitchHz: hz, pitchMidi: filtered);
    } else {
      _pitchState.updateUnvoiced(timeSec: time);
    }
    final f = PitchFrame(
      time: time,
      hz: hz,
      midi: voiced ? filtered : null,
      voicedProb: voicedProb,
      rms: rms,
    );
    _capturedFrames.add(f);
  }

  double _accuracyPercent() {
    if (_capturedFrames.isEmpty) return 0;
    final metrics = _scoring.score(_attachCents(_capturedFrames));
    return metrics.pctWithin50.clamp(0, 100);
  }

  String _formatTime(double t) {
    final totalSeconds = t.clamp(0, 24 * 60 * 60).floor();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _restart() async {
    if (_playing) {
      await _togglePlayback(force: false);
    }
    _timeNotifier.value = 0;
    _tailBuffer.clear();
    _capturedFrames.clear();
    _lastRecordingPath = null;
    _pitchBall.reset();
    _pitchState.reset();
    _visualState.reset();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Pitch Highway'),
      ),
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePlayback,
            child: Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                      return CustomPaint(
                        painter: PitchHighwayPainter(
                          notes: _notesWithLeadIn,
                          pitchTail: const [],
                          tailPoints: _tailBuffer.points,
                          time: _timeNotifier,
                          liveMidi: _liveMidi,
                          pitchTailTimeOffsetSec: 0,
                          pixelsPerSecond: pixelsPerSecond,
                          playheadFraction: playheadFraction,
                          drawBackground: false,
                          midiMin: midiRange.min,
                          midiMax: midiRange.max,
                          colors: colors,
                        ),
                      );
                    },
                  ),
                ),
                if (_showDebugOverlay)
                  DebugOverlay(
                    audioPositionMs:
                        _audioPositionSec == null ? null : _audioPositionSec! * 1000.0,
                    visualTimeMs: _timeNotifier.value * 1000.0,
                    pitchLagMs: _pitchBall.estimateLagMs(_timeNotifier.value),
                    offsetMs: _manualOffsetMs,
                    onOffsetChange: (value) {
                      setState(() => _manualOffsetMs = value);
                      _clock.setLatencyCompensationMs(_audioLatencyMs + _manualOffsetMs);
                    },
                    label: 'Pitch Highway',
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ValueListenableBuilder<double>(
                            valueListenable: _timeNotifier,
                            builder: (_, v, __) => Text(
                              _formatTime(v),
                              style: TextStyle(color: colors.textSecondary),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  color: colors.surface2,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                alignment: Alignment.centerLeft,
                                child: ValueListenableBuilder<double>(
                                  valueListenable: _timeNotifier,
                                  builder: (_, v, __) {
                                    final pct = (v / _totalDuration).clamp(0.0, 1.0);
                                    return FractionallySizedBox(
                                      widthFactor: pct,
                                      child: Container(
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: colors.accentPurple,
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          Text(
                            _formatTime(_totalDuration),
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
