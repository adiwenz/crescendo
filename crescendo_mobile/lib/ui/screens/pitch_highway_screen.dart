import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../debug/debug_log.dart';
import '../../models/pitch_highway_difficulty.dart';
import '../../models/vocal_exercise.dart';
import '../../models/pitch_highway_spec.dart';
import '../../models/pitch_segment.dart';
import '../../models/reference_note.dart';
import '../../models/pitch_frame.dart';
import '../../services/pitch_highway_session_controller.dart';
import '../../services/recording_service.dart';
import '../../audio/ref_audio/wav_cache_manager.dart';
import '../../audio/ref_audio/ref_spec.dart';
import '../../services/transposed_exercise_builder.dart';
import '../../services/vocal_range_service.dart';
import '../../services/reference_audio_generator.dart';
import '../../utils/audio_constants.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/app_background.dart';
import '../../ui/widgets/pitch_highway_painter.dart';
import '../../utils/pitch_tail_buffer.dart';
import '../../utils/pitch_highway_tempo.dart';
import '../../core/app_config.dart'; // Import AppConfig
import '../../theme/ballad_theme.dart';
import '../../widgets/ballad_scaffold.dart';
import 'review_last_take_v2_screen.dart';

import '../../services/progress_service.dart';
import '../../services/exercise_metadata.dart';

class PitchHighwayScreen extends StatefulWidget {
  final VocalExercise exercise;
  final PitchHighwayDifficulty pitchDifficulty;

  const PitchHighwayScreen({
    super.key,
    required this.exercise,
    required this.pitchDifficulty,
  });

  @override
  State<PitchHighwayScreen> createState() => _PitchHighwayScreenState();
}

class _PitchHighwayScreenState extends State<PitchHighwayScreen> {
  PitchHighwaySessionController? _controller;
  
  // Data Loading State
  bool _isLoading = true;
  String? _error;
  List<ReferenceNote> _notes = [];
  
  // Visuals
  final ValueNotifier<double> _visualTime = ValueNotifier(0.0);
  final ValueNotifier<double?> _liveMidi = ValueNotifier(null); // For future pitch ball support
  
  int _midiMin = 48;
  int _midiMax = 72;
  double _pixelsPerSecond = 100;
  
  bool _navigatedToReview = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      debugPrint('[V2] Loading data for ${widget.exercise.name}...');
      
      // 1. Range
      final range = await VocalRangeService().getRange();
      _midiMin = (range.$1 > 0 ? range.$1 : 48) - 3;
      _midiMax = (range.$2 > 0 ? range.$2 : 72) + 3;
      
      // 2. Tempo / Spec
      final spec = widget.exercise.highwaySpec;
      final segments = spec?.segments ?? const <PitchSegment>[];
      
      // 3. Notes
      debugPrint('[V2] preparing plan...');
      
      final refSpec = RefSpec(
        exerciseId: widget.exercise.id,
        lowMidi: range.$1,
        highMidi: range.$2,
        extraOptions: {'difficulty': widget.pitchDifficulty.name},
        renderVersion: 'v2',
      );
      
      final plan = await WavCacheManager.instance.get(refSpec, exercise: widget.exercise);
      
      if (!mounted) return;
      
      _notes = plan.notes;
      _pixelsPerSecond = PitchHighwayTempo.pixelsPerSecondFor(widget.pitchDifficulty);

      // 4. Init Controller
      debugPrint('[PitchHighway] Initializing controller with ${_notes.length} notes...');
      _controller = PitchHighwaySessionController(
        notes: _notes,
        referenceDurationSec: plan.durationSec,
        ensureReferenceWav: () async => plan.wavFilePath, 
        ensureRecordingPath: () async {
          final dir = await getTemporaryDirectory();
          return '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';
        },
        recorderFactory: () => RecordingService(owner: 'pitch_highway_v2', bufferSize: 1024),
      );

      await _controller?.prepare();

      setState(() {
        _isLoading = false;
      });
      
      debugPrint('[V2] Ready. Auto-starting...');
      if (mounted) {
         _controller?.start();
      }

    } catch (e, stack) {
      debugPrint('[V2] Error loading: $e');
      debugPrintStack(stackTrace: stack);
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _visualTime.dispose();
    _liveMidi.dispose();
    super.dispose();
  }
  
  void _onExit() {
    if (_controller == null) {
      Navigator.of(context).pop();
      return;
    }
    
    final state = _controller!.state.value;
    if (state.phase == PitchHighwaySessionPhase.recording) {
      // If recording, stop and let it proceed to review
      debugPrint('[V2] Early exit requested. Stopping recording to proceed to review.');
      _controller!.stop();
    } else if (state.phase == PitchHighwaySessionPhase.processing) {
      // Already processing, just wait
      debugPrint('[V2] Early exit requested but already processing. Ignoring.');
    } else {
      // Idle, Replay, or otherwise done
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(child: Text('Error: $_error')),
      );
    }

    if (_isLoading || _controller == null) {
      return BalladScaffold(
        title: widget.exercise.name,
        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return BalladScaffold(
      title: widget.exercise.name,
      padding: EdgeInsets.zero,
      useSafeArea: false,
      child: ValueListenableBuilder<PitchHighwaySessionState>(
        valueListenable: _controller!.state,
        builder: (context, state, _) {
          
          // Sync visual time to painter
          if (state.phase == PitchHighwaySessionPhase.recording) {
            _visualTime.value = state.recordVisualTimeSec;
          } else if (state.phase == PitchHighwaySessionPhase.processing || state.phase == PitchHighwaySessionPhase.replay) {
            // Keep visual time at the end position so the screen doesn't jump
            _visualTime.value = state.recordVisualTimeSec;
          } else {
            _visualTime.value = 0;
          }

          // Navigation to Review
          if (state.phase == PitchHighwaySessionPhase.replay && !_navigatedToReview) {
             // Only navigate if we have results
             if (state.offsetResult != null && state.referencePath != null && state.recordingPath != null) {
                 _navigatedToReview = true;
                 
                 // V0: Skip review, just finish
                 if (AppConfig.isV0) {
                   WidgetsBinding.instance.addPostFrameCallback((_) async {
                     // PERSIST ATTEMPT BEFORE EXITING
                     final score = (state.offsetResult?.confidence ?? 0.0) * 100;
                     final attempt = ProgressService().buildAttempt(
                       exerciseId: widget.exercise.id,
                       categoryId: widget.exercise.categoryId,
                       startedAt: _controller?.recordStartTime ?? DateTime.now().subtract(Duration(seconds: state.recordVisualTimeSec.toInt())),
                       completedAt: DateTime.now(),
                       overallScore: score,
                       recordingPath: state.recordingPath,
                       recorderStartSec: state.offsetResult?.offsetMs != null ? state.offsetResult!.offsetMs / 1000.0 : 0.0,
                       referenceWavPath: state.referencePath,
                       referenceSampleRate: 44100, // standard
                       countsForDailyEffort: true,
                       contourJson: null, // We have the frames in alignedFrames, but ProgressService persistAttempt expects JSON or File?
                       // Wait, persistAttempt handles file assets if we give it recordingPath/contourJson
                     );
                     
                     // We need to convert frames to JSON if we want them saved for detailed review later
                     // But for now, saving the score and paths is the priority
                     
                     try {
                        await ProgressService().persistAttempt(attempt: attempt);
                        debugPrint('[PitchHighway] V0 Auto-save OK');
                     } catch (e) {
                        debugPrint('[PitchHighway] V0 Auto-save FAILED: $e');
                     }

                     if (context.mounted) Navigator.of(context).pop();
                   });
                   return Container(); // Return empty to avoid painting review logic
                 }

                 WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (context.mounted) {
                       Navigator.of(context).pushReplacement(
                         MaterialPageRoute(
                           builder: (_) => ReviewLastTakeV2Screen(
                             notes: _notes,
                             referencePath: state.referencePath!,
                             recordingPath: state.recordingPath!,
                             offsetResult: state.offsetResult!,
                             referenceDurationSec: _controller?.referenceDurationSec ?? 0,
                             alignedFrames: state.alignedFrames,
                           ),
                         ),
                       );
                    }
                 });
             }
             // Do NOT return early here - let the UI paint the frozen state
          }

          final now = _visualTime.value;
          final visibleFrames = state.capturedFrames.where((f) => 
              f.time > now - 4.0 && 
              f.time <= now && 
              f.time > AudioConstants.totalChirpOffsetSec // Hide pitch during chirp
          );
          
          return Stack(
            children: [
              // 1. Background / Painter (Recording, Idle, Processing, Replay)
              if (state.phase != PitchHighwaySessionPhase.idle || state.phase == PitchHighwaySessionPhase.idle) // Effectively always true, but keeps logic structure
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () {
                      debugPrint('[V2] Tap to exit triggered');
                      _onExit();
                    },
                    behavior: HitTestBehavior.translucent,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                         // Rebuild points
                         final points = visibleFrames.map((f) {
                            // We need Y coordinate.
                            final midi = f.midi ?? 0;
                            final y = (constraints.maxHeight) - ((midi - _midiMin) / (_midiMax - _midiMin)) * constraints.maxHeight;
                            return TailPoint(tSec: f.time, yPx: y, voiced: (f.voicedProb??0) > 0.5); 
                         }).toList();

                         return CustomPaint(
                           painter: PitchHighwayPainter(
                             notes: _notes, 
                             pitchTail: const [], 
                             tailPoints: points, 
                             time: _visualTime,
                             liveMidi: _liveMidi, 
                             pitchTailTimeOffsetSec: 0,
                             pixelsPerSecond: _pixelsPerSecond,
                             playheadFraction: 0.45,
                             drawBackground: true,
                             midiMin: _midiMin,
                             midiMax: _midiMax,
                             colors: AppThemeColors.dark,
                           ),
                         );
                      }
                    ),
                  ),
                ),
                
              // 3. Processing
               if (state.phase == PitchHighwaySessionPhase.processing)
                 Container(
                   color: BalladTheme.bgTop.withOpacity(0.8), 
                   child: const Center(child: CircularProgressIndicator(color: Colors.white))
                 ),

              // 4. Overlays / Start Button (Idle) -> REMOVED
              
              // Debug Text - Hid in V0 and cleaned up
              if (!AppConfig.isV0)
                Positioned(
                   top: MediaQuery.of(context).padding.top + 50, right: 20,
                   child: Text("${state.phase.name}", style: TextStyle(color: Colors.white.withOpacity(0.3))),
                ),
              
              // Close Button - REMOVED redundant button as AppBar provides it
            ],
          );
        },
      ),
    );
  }
}
