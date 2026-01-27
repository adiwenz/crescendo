import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:audio_session/audio_session.dart';


import '../../services/pitch_service.dart';
import '../../services/audio_session_manager.dart';
import '../../utils/audio_constants.dart';
import '../../ui/route_observer.dart';
import '../widgets/cents_meter.dart';
import '../widgets/piano_keyboard.dart';
import '../../services/midi_route_manager.dart';
import '../../audio/reference_midi_synth.dart';

// Pitch detection configuration constants
class PitchDetectionConfig {
  // Confidence threshold - only update highlighted key if confidence >= this
  static const double confidenceThreshold = 0.6;
  
  // Stability requirement - note must be stable for this duration before changing
  static const Duration stabilityDuration = Duration(milliseconds: 200);
  
  // Median filter window size (must be odd, e.g., 5, 7, 9)
  static const int medianWindowSize = 7;
  
  // EMA alpha for second-stage smoothing (0.0-1.0, higher = more responsive)
  static const double emaAlpha = 0.3;
  
  // Octave jump protection: require higher confidence for ±12 semitone jumps
  static const double octaveJumpConfidenceMultiplier = 1.5;
  static const int octaveJumpStabilityFrames = 5; // Extra frames required for octave jumps
  
  // UI update throttling (fps)
  static const int uiUpdateFps = 45; // Update UI at 45fps
  static const Duration uiUpdateInterval = Duration(milliseconds: 1000 ~/ uiUpdateFps);
}

class PianoPitchScreen extends StatefulWidget {
  const PianoPitchScreen({super.key});

  @override
  State<PianoPitchScreen> createState() => _PianoPitchScreenState();
}

class _PianoPitchScreenState extends State<PianoPitchScreen> with RouteAware, WidgetsBindingObserver {
  final ReferenceMidiSynth _midi = ReferenceMidiSynth.instance;
  final MidiRouteManager _routeManager = MidiRouteManager.instance;
  bool _midiReady = false;
  late final PitchService _service;
  late final PitchTracker _tracker;
  StreamSubscription<PitchFrame>? _sub;
  final ScrollController _keyboardController = ScrollController();
  static const double _keyHeight = 36;
  bool _initialScrollSet = false;
  bool _isVisible = false;
  
  // Debug overlay state
  // Set to true to show audio debug overlay (toggle with long-press on overlay)
  static const bool _kShowDebugOverlay = false; // Change this to true to enable debug overlay
  bool _showDebugOverlay = _kShowDebugOverlay;
  String _audioRoute = 'Unknown';
  int _sampleRate = AudioConstants.audioSampleRate;
  int _bufferSize = 1024;
  bool _micPermissionGranted = false;
  DateTime? _lastUiUpdate;

  @override
  void initState() {
    super.initState();
    debugPrint('[PianoPitchScreen] initState');
    _service = PitchService.instance;
    _tracker = PitchTracker();
    _isVisible = true;
    WidgetsBinding.instance.addObserver(this);
    
    // Defer MIDI initialization until after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAudioSession();
      _initRouteManager();
      _initMidi();
      _centerKeyboardInitial();
    });
  }

  Future<void> _initRouteManager() async {
    await _routeManager.init();
  }

  Future<void> _initMidi() async {
    try {
      debugPrint('[PianoPitchScreen] Initializing MIDI...');
      await _midi.init();
      _midiReady = true;
      debugPrint('[PianoPitchScreen] MIDI initialized successfully');
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[PianoPitchScreen] MIDI initialization failed: $e');
      _midiReady = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _initAudioSession() async {
    try {
      await AudioSession.instance; // Initialize audio session
      _micPermissionGranted = await AudioSessionManager.instance.hasPermission();
      
      // Get initial route info (simplified - audio_session may not expose route directly)
      // We'll update this when we can get route information
      _audioRoute = 'Built-in Mic'; // Default
      
      // Get sample rate and buffer size from RecordingService
      // These are set in RecordingService constructor
      _sampleRate = AudioConstants.audioSampleRate; // Default, will be updated from actual recording
      _bufferSize = 1024; // Updated to match RecordingService default for piano
      
      // Log audio session info
      debugPrint('[PianoPitchScreen] Audio session initialized: route=$_audioRoute, sampleRate=$_sampleRate, bufferSize=$_bufferSize, micPermission=$_micPermissionGranted');
      
      setState(() {});
    } catch (e) {
      debugPrint('[PianoPitchScreen] Error initializing audio session: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
      debugPrint('[PianoPitchScreen] Subscribed to route observer');
    }
  }

  @override
  @override
  void didPush() {
    debugPrint('[PianoPitchScreen] didPush - Piano screen appearing');
    _isVisible = true;
    _start();
  }

  @override
  void didPop() {
    debugPrint('[PianoPitchScreen] didPop - Piano screen removed');
    _isVisible = false;
    _stop();
  }

  @override
  void didPopNext() {
    debugPrint('[PianoPitchScreen] didPopNext - returning to Piano screen');
    _isVisible = true;
    _start();
  }

  @override
  void didPushNext() {
    debugPrint('[PianoPitchScreen] didPushNext - navigating away from Piano');
    _isVisible = false;
    _stop();
  }

  void _ensureStreamSubscription() {
    if (_sub == null || _sub!.isPaused) {
      debugPrint('[PianoPitchScreen] Re-establishing stream subscription');
      _sub?.cancel();
      int _frameCount = 0;
      _sub = _service.stream.listen(
        (frame) {
          _frameCount++;
          final now = DateTime.now();
          
          // Log first frame to confirm stream is working
          if (_frameCount == 1) {
            debugPrint('[PianoPitchScreen] 🎉 FIRST FRAME RECEIVED! Stream is active. freq=${frame.frequencyHz.toStringAsFixed(1)}Hz, conf=${frame.confidence.toStringAsFixed(2)}');
          }
          
          // Update tracker (runs at high rate, ~50-100Hz)
          _tracker.updateFromReading(frame);
          
          // Throttle UI updates to 45fps
          if (_lastUiUpdate == null || 
              now.difference(_lastUiUpdate!) >= PitchDetectionConfig.uiUpdateInterval) {
            _lastUiUpdate = now;
            if (mounted) {
              setState(() {
                // Trigger UI rebuild via AnimatedBuilder in tracker
              });
            }
          }
        },
        onError: (error) {
          debugPrint('[PianoPitchScreen] ⚠️ STREAM ERROR: $error');
          _restartPitchDetection();
        },
        onDone: () {
          debugPrint('[PianoPitchScreen] ⚠️ STREAM DONE - stream closed unexpectedly');
          _restartPitchDetection();
        },
        cancelOnError: false,
      );
      debugPrint('[PianoPitchScreen] ✅ Stream subscription established');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isVisible) {
      debugPrint('[PianoPitchScreen] App resumed, ensuring pitch detection is running');
      if (!_service.isRunning) {
        _restartPitchDetection();
      } else {
        _ensureStreamSubscription();
      }
    }
  }

  Future<void> _start() async {
    if (!mounted || !_isVisible) {
      debugPrint('[PianoPitchScreen] ⚠️ Skipping start - not mounted or not visible');
      return;
    }
    debugPrint('[PianoPitchScreen] 🎹 Starting pitch detection...');
    try {
      if (_service.isRunning) {
        debugPrint('[PianoPitchScreen] Service already running, ensuring subscription...');
        _ensureStreamSubscription();
        return;
      }
      
      await _service.start();
      _ensureStreamSubscription();
      debugPrint('[PianoPitchScreen] ✅✅ Pitch detection started');
    } catch (e, stackTrace) {
      debugPrint('[PianoPitchScreen] ❌ ERROR starting pitch detection: $e');
      debugPrint('[PianoPitchScreen] Stack trace: $stackTrace');
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _isVisible) {
          _restartPitchDetection();
        }
      });
    }
  }

  Future<void> _stop() async {
    debugPrint('[PianoPitchScreen] Stopping pitch detection UI...');
    await _sub?.cancel();
    _sub = null;
    try {
      if (_service.isRunning) {
        await _service.stop();
      }
    } catch (e) {
      debugPrint('[PianoPitchScreen] Error stopping service: $e');
    }
  }

  Future<void> _restartPitchDetection() async {
    if (!mounted || !_isVisible) return;
    debugPrint('[PianoPitchScreen] Restarting pitch detection...');
    await _stop();
    await AudioSessionManager.instance.forceReleaseAll();
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted && _isVisible) {
      await _start();
    }
  }

  @override
  void dispose() {
    debugPrint('[PianoPitchScreen] dispose START');
    _isVisible = false;
    WidgetsBinding.instance.removeObserver(this);
    try {
      routeObserver.unsubscribe(this);
      debugPrint('[PianoPitchScreen] Unsubscribed from route observer');
    } catch (e) {
      debugPrint('[PianoPitchScreen] Error unsubscribing: $e');
    }
    _sub?.cancel();
    _sub = null;
    
    // Dispose services
    _service.dispose();
    _keyboardController.dispose();
    _tracker.dispose();
    _routeManager.dispose();
    debugPrint('[PianoPitchScreen] dispose END');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final keyboardWidth =
                    (constraints.maxWidth * 0.32).clamp(90.0, 160.0).toDouble();
                return Row(
                  children: [
                    SizedBox(
                      width: keyboardWidth,
                      child: Scrollbar(
                        thumbVisibility: true,
                        controller: _keyboardController,
                        child: SingleChildScrollView(
                          primary: false,
                          controller: _keyboardController,
                          reverse: false,
                          child: AnimatedBuilder(
                            animation: _tracker,
                            builder: (_, __) => PianoKeyboard(
                              startMidi: _tracker.rangeStartNote,
                              endMidi: _tracker.rangeEndNote,
                              highlightedMidi: _tracker.currentMidi,
                              onKeyTap: _handleKeyTap,
                              keyHeight: _keyHeight,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                            child: Text(
                              'Piano Pitch',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: AnimatedBuilder(
                                animation: _tracker,
                                builder: (_, __) {
                                  final note = _tracker.currentNoteName ?? '—';
                                  final freq = _tracker.currentFreqHz;
                                  final freqLabel =
                                      freq == null ? '—' : '${freq.toStringAsFixed(1)} Hz';
                                  final cents = _tracker.centsOff;
                                  final inTune = cents != null && cents.abs() <= 10;
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        note,
                                        style: Theme.of(context)
                                            .textTheme
                                            .displaySmall
                                            ?.copyWith(fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        freqLabel,
                                        style: Theme.of(context).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 24),
                                      CentsMeter(
                                        cents: cents,
                                        confidence: _tracker.confidence ?? 0,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        inTune ? 'In tune' : 'Adjust pitch',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                              color: inTune ? Colors.green : Colors.black54,
                                            ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        'Range: ${_tracker.rangeLabel}',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            // Debug overlay (toggle with long-press)
            if (_showDebugOverlay)
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onLongPress: () {
                    setState(() {
                      _showDebugOverlay = !_showDebugOverlay;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Audio Debug',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Route: $_audioRoute',
                          style: TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                        Text(
                          'Sample Rate: ${_sampleRate}Hz',
                          style: TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                        Text(
                          'Buffer: $_bufferSize',
                          style: TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                        Text(
                          'Mic: ${_micPermissionGranted ? "✓" : "✗"}',
                          style: TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                        const SizedBox(height: 4),
                        AnimatedBuilder(
                          animation: _tracker,
                          builder: (_, __) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Freq: ${_tracker.currentFreqHz?.toStringAsFixed(1) ?? "—"} Hz',
                                  style: TextStyle(color: Colors.white70, fontSize: 10),
                                ),
                                Text(
                                  'MIDI: ${_tracker.currentMidi ?? "—"}',
                                  style: TextStyle(color: Colors.white70, fontSize: 10),
                                ),
                                Text(
                                  'Note: ${_tracker.currentNoteName ?? "—"}',
                                  style: TextStyle(color: Colors.white70, fontSize: 10),
                                ),
                                Text(
                                  'Conf: ${(_tracker.confidence ?? 0).toStringAsFixed(2)}',
                                  style: TextStyle(color: Colors.white70, fontSize: 10),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _handleKeyTap(int midi) {
    _tracker.setManualMidi(midi);
    _playTapTone(midi);
  }

  void _centerKeyboardInitial() {
    if (_initialScrollSet) return;
    _initialScrollSet = true;
    _centerKeyboardOnMidi(60);
  }

  void _centerKeyboardOnMidi(int midi) {
    if (!_keyboardController.hasClients) return;
    final whiteKeys = _whiteKeys(_tracker.rangeStartNote, _tracker.rangeEndNote);
    final index = whiteKeys.indexOf(midi);
    if (index == -1) return;
    final viewport = _keyboardController.position.viewportDimension;
    final target = (index * _keyHeight) - (viewport / 2) + (_keyHeight / 2);
    final clamped =
        target.clamp(0.0, _keyboardController.position.maxScrollExtent);
    _keyboardController.jumpTo(clamped);
  }

  List<int> _whiteKeys(int start, int end) {
    final keys = <int>[];
    for (var midi = start; midi <= end; midi++) {
      if (_isWhite(midi)) keys.add(midi);
    }
    return keys.reversed.toList();
  }

  bool _isWhite(int midi) {
    const white = {0, 2, 4, 5, 7, 9, 11};
    return white.contains(midi % 12);
  }

  void _playTapTone(int midi) {
    if (!_midiReady) {
      debugPrint('[PianoPitchScreen] MIDI not ready, cannot play note');
      return;
    }

    // Play note immediately
    _midi.playNote(midi, velocity: 100);

    // Stop note after 600ms (matching the original duration)
    Future.delayed(const Duration(milliseconds: 600), () {
      _midi.stopNote(midi);
    });
  }
}

class PitchTracker extends ChangeNotifier {
  int rangeStartNote = 24; // C1
  int rangeEndNote = 96; // C7
  double? currentFreqHz;
  double? confidence;
  int? currentMidi;
  String? currentNoteName;
  double? centsOff;

  // Configuration
  final double _confidenceThreshold = PitchDetectionConfig.confidenceThreshold;
  final Duration _stabilityDuration = PitchDetectionConfig.stabilityDuration;
  final int _medianWindowSize = PitchDetectionConfig.medianWindowSize;
  final double _emaAlpha = PitchDetectionConfig.emaAlpha;
  final double _octaveJumpConfidenceMultiplier = PitchDetectionConfig.octaveJumpConfidenceMultiplier;
  final int _octaveJumpStabilityFrames = PitchDetectionConfig.octaveJumpStabilityFrames;

  // State
  DateTime? _lastValidTs;
  double? _smoothedFreq;
  double? _smoothedCents;
  int? _stableMidi;
  DateTime? _stableMidiTimestamp; // When current stable MIDI was first detected (used for stability check)
  final List<double> _frequencyHistory = []; // For median filter
  final List<DateTime> _frequencyHistoryTimestamps = [];
  
  // Hysteresis: keep current note if new candidate is close but not stable enough
  int? _pendingMidi;
  int _pendingCount = 0;
  DateTime? _pendingMidiTimestamp;

  String get rangeLabel => '${_noteName(rangeStartNote)}–${_noteName(rangeEndNote)}';

  void updateFromReading(PitchFrame frame) {
    final freq = frame.frequencyHz;
    final conf = frame.confidence;
    confidence = conf;

    // Confidence gating: only process if confidence is sufficient
    final valid = conf >= _confidenceThreshold && freq > 0 && freq.isFinite;
    if (!valid) {
      // Hold last valid reading for a short time
      if (_lastValidTs != null &&
          frame.ts.difference(_lastValidTs!) <= _stabilityDuration) {
        notifyListeners();
        return;
      }
      // Clear after hold duration expires
      _clear();
      notifyListeners();
      return;
    }

    _lastValidTs = frame.ts;

    // Median filter on frequency
    _frequencyHistory.add(freq);
    _frequencyHistoryTimestamps.add(frame.ts);
    if (_frequencyHistory.length > _medianWindowSize) {
      _frequencyHistory.removeAt(0);
      _frequencyHistoryTimestamps.removeAt(0);
    }
    
    // Compute median
    final sorted = List<double>.from(_frequencyHistory)..sort();
    final medianFreq = sorted[sorted.length ~/ 2];
    
    // Apply EMA smoothing as second stage
    _smoothedFreq = _smooth(_smoothedFreq, medianFreq, _emaAlpha);
    currentFreqHz = _smoothedFreq;

    // Convert to MIDI
    final midiRaw = 69 + 12 * (math.log(_smoothedFreq! / 440.0) / math.ln2);
    final candidateMidi = midiRaw.round();
    
    // Octave jump protection
    final isOctaveJump = _stableMidi != null && 
                         (candidateMidi - _stableMidi!).abs() >= 12;
    
    // Stability requirement
    final now = frame.ts;
    final requiredConfidence = isOctaveJump 
        ? _confidenceThreshold * _octaveJumpConfidenceMultiplier
        : _confidenceThreshold;
    
    final requiredStabilityFrames = isOctaveJump
        ? _octaveJumpStabilityFrames
        : 1;
    
    // Check if candidate meets confidence requirement
    if (conf < requiredConfidence) {
      // Confidence too low - keep current note (hysteresis)
      notifyListeners();
      return;
    }
    
    // Update pending/stable MIDI with stability requirement
    if (_stableMidi == null) {
      // No stable note yet - start tracking candidate
      _stableMidi = candidateMidi;
      _stableMidiTimestamp = now;
      _pendingMidi = null;
      _pendingCount = 0;
    } else if (candidateMidi == _stableMidi) {
      // Same note - continue tracking
      _pendingMidi = null;
      _pendingCount = 0;
    } else {
      // Different note - check stability
      if (_pendingMidi == candidateMidi) {
        _pendingCount++;
      } else {
        _pendingMidi = candidateMidi;
        _pendingCount = 1;
        _pendingMidiTimestamp = now;
      }
      
      // Check if candidate has been stable long enough
      final candidateStableDuration = _pendingMidiTimestamp != null
          ? now.difference(_pendingMidiTimestamp!)
          : Duration.zero;
      
      final candidateStableFrames = _pendingCount;
      
      // Also check if current stable note has been held long enough (for stability requirement)
      final currentStableDuration = _stableMidiTimestamp != null
          ? now.difference(_stableMidiTimestamp!)
          : Duration.zero;
      
      if (candidateStableFrames >= requiredStabilityFrames &&
          candidateStableDuration >= _stabilityDuration &&
          currentStableDuration >= _stabilityDuration) {
        // Candidate is stable - accept it
        _stableMidi = candidateMidi;
        _stableMidiTimestamp = now;
        _pendingMidi = null;
        _pendingCount = 0;
      } else {
        // Candidate not stable yet - keep current note (hysteresis)
        // Don't update currentMidi, just notify for UI refresh
        notifyListeners();
        return;
      }
    }
    
    // Update current MIDI and note name
    currentMidi = _stableMidi;
    currentNoteName = _stableMidi == null ? null : _noteName(_stableMidi!);
    
    // Compute cents off
    if (_stableMidi != null) {
      final rawCents = (midiRaw - _stableMidi!) * 100;
      _smoothedCents = _smooth(_smoothedCents, rawCents, _emaAlpha);
      centsOff = _smoothedCents?.clamp(-50.0, 50.0);
    } else {
      centsOff = null;
    }

    notifyListeners();
  }

  void setManualMidi(int midi) {
    final freq = 440.0 * math.pow(2.0, (midi - 69) / 12.0);
    currentFreqHz = freq;
    confidence = 1.0;
    _stableMidi = midi;
    _stableMidiTimestamp = DateTime.now();
    currentMidi = midi;
    currentNoteName = _noteName(midi);
    centsOff = 0.0;
    _lastValidTs = DateTime.now();
    _pendingMidi = null;
    _pendingCount = 0;
    _frequencyHistory.clear();
    _frequencyHistoryTimestamps.clear();
    _frequencyHistory.add(freq);
    _frequencyHistoryTimestamps.add(DateTime.now());
    notifyListeners();
  }

  double _smooth(double? prev, double next, double alpha) {
    if (prev == null) return next;
    return prev + alpha * (next - prev);
  }

  void _clear() {
    currentFreqHz = null;
    currentMidi = null;
    currentNoteName = null;
    centsOff = null;
    _stableMidi = null;
    _stableMidiTimestamp = null;
    _pendingMidi = null;
    _pendingCount = 0;
    _smoothedCents = null;
    _smoothedFreq = null;
    _frequencyHistory.clear();
    _frequencyHistoryTimestamps.clear();
  }

  String _noteName(int midi) {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (midi / 12).floor() - 1;
    return '${names[midi % 12]}$octave';
  }
}
