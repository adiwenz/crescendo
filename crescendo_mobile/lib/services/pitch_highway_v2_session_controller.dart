import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../services/audio_offset_estimator.dart';
import '../services/audio_session_service.dart';
import '../services/recording_service.dart';
import '../models/reference_note.dart';
import '../models/pitch_frame.dart';
import '../utils/replay_alignment_model.dart';

enum PitchHighwaySessionPhase { idle, recording, processing, replay }

@immutable
class PitchHighwaySessionState {
  final PitchHighwaySessionPhase phase;
  final List<ReferenceNote> notes;
  final List<PitchFrame> capturedFrames;
  final List<PitchFrame> alignedFrames;
  final String? referencePath;
  final String? recordingPath;
  final AudioOffsetResult? offsetResult;

  // Replay controls
  final bool isPlayingReplay;
  final bool applyOffset;
  final double refVolume;
  final double recVolume;

  // Timing for UI
  final double recordVisualTimeSec;
  final double replayVisualTimeSec;

  const PitchHighwaySessionState({
    this.phase = PitchHighwaySessionPhase.idle,
    this.notes = const [],
    this.capturedFrames = const [],
    this.alignedFrames = const [],
    this.referencePath,
    this.recordingPath,
    this.offsetResult,
    this.isPlayingReplay = false,
    this.applyOffset = true,
    this.refVolume = 1.0,
    this.recVolume = 1.0,
    this.recordVisualTimeSec = 0.0,
    this.replayVisualTimeSec = 0.0,
  });

  PitchHighwaySessionState copyWith({
    PitchHighwaySessionPhase? phase,
    List<ReferenceNote>? notes,
    List<PitchFrame>? capturedFrames,
    List<PitchFrame>? alignedFrames,
    String? referencePath,
    String? recordingPath,
    AudioOffsetResult? offsetResult,
    bool? isPlayingReplay,
    bool? applyOffset,
    double? refVolume,
    double? recVolume,
    double? recordVisualTimeSec,
    double? replayVisualTimeSec,
  }) {
    return PitchHighwaySessionState(
      phase: phase ?? this.phase,
      notes: notes ?? this.notes,
      capturedFrames: capturedFrames ?? this.capturedFrames,
      alignedFrames: alignedFrames ?? this.alignedFrames,
      referencePath: referencePath ?? this.referencePath,
      recordingPath: recordingPath ?? this.recordingPath,
      offsetResult: offsetResult ?? this.offsetResult,
      isPlayingReplay: isPlayingReplay ?? this.isPlayingReplay,
      applyOffset: applyOffset ?? this.applyOffset,
      refVolume: refVolume ?? this.refVolume,
      recVolume: recVolume ?? this.recVolume,
      recordVisualTimeSec: recordVisualTimeSec ?? this.recordVisualTimeSec,
      replayVisualTimeSec: replayVisualTimeSec ?? this.replayVisualTimeSec,
    );
  }
}

class PitchHighwayV2SessionController {
  PitchHighwayV2SessionController({
    required List<ReferenceNote> notes,
    required this.referenceDurationSec,
    required this.ensureReferenceWav,
    required this.ensureRecordingPath,
    required this.recorderFactory,
    AudioPlayer? referencePlayer,
    AudioPlayer? replayReferencePlayer,
    AudioPlayer? replayRecordingPlayer,
  }) : _notes = notes,
       _refPlayer = referencePlayer ?? AudioPlayer(),
       _refReplayPlayer = replayReferencePlayer ?? AudioPlayer(),
       _recPlayer = replayRecordingPlayer ?? AudioPlayer() {
     // Initialize state
     state = ValueNotifier(PitchHighwaySessionState(notes: notes));
     
     // Auto-stop replay when players finish
     _refReplayPlayer.onPlayerComplete.listen((_) => _onReplayComplete());
  }

  final List<ReferenceNote> _notes;
  final double referenceDurationSec;
  final Future<String> Function() ensureReferenceWav;
  final Future<String> Function() ensureRecordingPath;
  final RecordingService Function() recorderFactory;

  // Players
  final AudioPlayer _refPlayer;
  final AudioPlayer _refReplayPlayer;
  final AudioPlayer _recPlayer;

  // State
  late final ValueNotifier<PitchHighwaySessionState> state;

  // Internals
  RecordingService? _recorder;
  StreamSubscription<PitchFrame>? _pitchSub;
  Timer? _recordTimer;
  Timer? _replayTimer;
  DateTime? _recordStartTime;
  DateTime? _replayStartTime;
  bool _isDisposed = false;
  
  // Throttle captured frames
  final List<PitchFrame> _internalFrames = [];

  // --- Lifecycle Methods ---

  Future<void> prepare() async {
    if (_isDisposed) return;
    final refPath = await ensureReferenceWav();
    if (_isDisposed) return;
    state.value = state.value.copyWith(
      phase: PitchHighwaySessionPhase.idle,
      referencePath: refPath,
    );
  }

  Future<void> start() async {
    if (_isDisposed) return;
    if (state.value.referencePath == null) return;

    // 1. Audio Session
    await AudioSessionService.applyExerciseSession();

    // 2. Paths
    final recPath = await ensureRecordingPath();
    if (_isDisposed) return;
    
    // 3. Reset internal state
    _internalFrames.clear();
    state.value = state.value.copyWith(
      phase: PitchHighwaySessionPhase.recording,
      recordingPath: recPath,
      capturedFrames: [],
      recordVisualTimeSec: 0.0,
    );

    // 4. Recorder
    _recorder = recorderFactory();
    
    // 5. Prepare Player
    await _refPlayer.setSourceDeviceFile(state.value.referencePath!);

    // 6. Start Recording
    await _recorder!.start(owner: 'pitch_highway_v2', mode: RecordingMode.take);
    
    _pitchSub = _recorder!.liveStream.listen((frame) {
      _internalFrames.add(frame);
    });

    // 7. Start Playback
    // Wait briefly to ensure mic is hot and captures the sync signal
    await Future.delayed(const Duration(milliseconds: 200));
    await _refPlayer.resume();
    _recordStartTime = DateTime.now();

    // 8. Start Visual Timer (~30Hz)
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (_isDisposed || state.value.phase != PitchHighwaySessionPhase.recording) {
        timer.cancel();
        return;
      }
      
      final now = DateTime.now();
      final elapsed = now.difference(_recordStartTime!).inMilliseconds / 1000.0;
      
      // Update state with new frames + time
      state.value = state.value.copyWith(
        recordVisualTimeSec: elapsed,
        capturedFrames: List.of(_internalFrames), // Shallow copy
      );

      // Auto-stop
      if (elapsed >= referenceDurationSec + 0.5) {
        stop();
      }
    });
  }

  Future<void> stop() async {
    if (_isDisposed) return;
    _recordTimer?.cancel();
    await _refPlayer.stop();
    
    if (_recorder != null) {
      final result = await _recorder!.stop(customPath: state.value.recordingPath);
      if (result != null) {
         debugPrint('[V2Controller] Waiting for WAV encoding...');
         await result.wavPathFuture;
         debugPrint('[V2Controller] WAV ready for offset calculation.');
      }
    }
    _pitchSub?.cancel();

    state.value = state.value.copyWith(
      phase: PitchHighwaySessionPhase.processing,
    );

    await computeOffset();
  }

  Future<void> computeOffset() async {
    if (_isDisposed) return;
    final refPath = state.value.referencePath;
    final recPath = state.value.recordingPath;

    if (refPath == null || recPath == null) return;

    final result = await AudioOffsetEstimator.estimateOffsetSamples(
      recordedPath: recPath,
      referencePath: refPath,
      strategy: OffsetStrategy.auto,
    );
    debugPrint('[PitchHighwayV2SessionController] ADRIANNA Offset result: $result');  
    
    if (_isDisposed) return;

    // Switch to playback session
    await AudioSessionService.applyReviewSession();

    // Prepare players
    if (recPath.isNotEmpty) {
       final f = File(recPath);
       if (await f.exists()) {
          await _recPlayer.setSourceDeviceFile(recPath);
       }
    }
    await _refReplayPlayer.setSourceDeviceFile(refPath);

    if (_isDisposed) return;
    
    // Compute aligned frames for replay
    List<PitchFrame> alignedFrames = [];
    if (result.confidence > 0.0) { // Or always
       final offsetSec = result.offsetMs / 1000.0;
       final model = ReplayAlignmentModel(micOffsetSec: offsetSec);
       
       alignedFrames = state.value.capturedFrames.map((f) {
         // Create copy with shifted time
         return PitchFrame(
           time: model.micTimeToExerciseTime(f.time),
           hz: f.hz,
           midi: f.midi,
           centsError: f.centsError,
           voicedProb: f.voicedProb,
           rms: f.rms,
         );
       }).toList();
       
       debugPrint('[V2Controller] Aligned ${alignedFrames.length} frames with offset ${offsetSec}s');
    }

    state.value = state.value.copyWith(
      offsetResult: result,
      phase: PitchHighwaySessionPhase.replay,
      alignedFrames: alignedFrames,
    );
  }

  Future<void> toggleReplay() async {
    if (_isDisposed) return;
    final s = state.value;
    if (s.isPlayingReplay) {
      // STOP
      _replayTimer?.cancel();
      await _refReplayPlayer.stop();
      await _recPlayer.stop();
      if (_isDisposed) return;
      state.value = s.copyWith(isPlayingReplay: false);
    } else {
      // START ALIGNED
      await _refReplayPlayer.stop();
      await _recPlayer.stop();

      final offsetMs = s.applyOffset ? (s.offsetResult?.offsetMs ?? 0) : 0;
      debugPrint('[PitchHighwayV2SessionController] ADRIANNA Starting replay with offset: $offsetMs ms');

      // Volumes
      await _refReplayPlayer.setVolume(s.refVolume);
      await _recPlayer.setVolume(s.recVolume * 8.0);

      // Reset sources to be safe
      if (s.referencePath != null) {
        await _refReplayPlayer.setSourceDeviceFile(s.referencePath!);
      }
      if (s.recordingPath != null) {
        await _recPlayer.setSourceDeviceFile(s.recordingPath!);
      }

      if (_isDisposed) return;
      state.value = s.copyWith(isPlayingReplay: true);

      if (offsetMs > 0) {
        await _recPlayer.resume();
        debugPrint('[PitchHighwayV2SessionController] ADRIANNA _recPlayer.resume()');
        
        Future.delayed(Duration(milliseconds: offsetMs.toInt()), () async {
          if (!_isDisposed && state.value.isPlayingReplay) {
            await _refReplayPlayer.resume();
            _startReplayTimer();
          }
        });

      } else {
        await _refReplayPlayer.resume();
        _startReplayTimer();

        final delay = offsetMs.abs().toInt();
        Future.delayed(Duration(milliseconds: delay), () async {
          if (!_isDisposed && state.value.isPlayingReplay) {
             await _recPlayer.resume();
          }
        });
      }
    }
  }

  void _startReplayTimer() {
    _replayStartTime = DateTime.now();
    _replayTimer?.cancel();
    _replayTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) async {
      if (_isDisposed || !state.value.isPlayingReplay) {
        timer.cancel();
        return;
      }
      
      // Drive visuals from Reference Player position (the master clock)
      final pos = await _refReplayPlayer.getCurrentPosition();
      if (pos != null) {
        final t = pos.inMicroseconds / 1000000.0;
        state.value = state.value.copyWith(
          replayVisualTimeSec: t,
        );
      }
    });
  }

  void _onReplayComplete() {
    if (!_isDisposed && state.value.isPlayingReplay) {
      state.value = state.value.copyWith(isPlayingReplay: false);
      _replayTimer?.cancel();
      _recPlayer.stop();
      _refReplayPlayer.stop();
    }
  }

  // --- Setters ---

  void setApplyOffset(bool v) {
    if (_isDisposed) return;
    state.value = state.value.copyWith(applyOffset: v);
  }

  void setRefVolume(double v) {
    if (_isDisposed) return;
    state.value = state.value.copyWith(refVolume: v);
    _refReplayPlayer.setVolume(v);
  }

  void setRecVolume(double v) {
    if (_isDisposed) return;
    state.value = state.value.copyWith(recVolume: v);
    _recPlayer.setVolume(v * 8.0);
  }

  void dispose() {
    _isDisposed = true;
    _recordTimer?.cancel();
    _replayTimer?.cancel();
    _pitchSub?.cancel();
    
    _refPlayer.dispose();
    _refReplayPlayer.dispose();
    _recPlayer.dispose();
    _recorder?.dispose();
    
    state.dispose();
  }
}
