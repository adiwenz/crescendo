import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../models/reference_note.dart';
import '../../services/audio_synth_service.dart';
import '../../services/pitch_service.dart';
import '../../services/audio_session_manager.dart';
import '../../ui/route_observer.dart';
import '../widgets/cents_meter.dart';
import '../widgets/piano_keyboard.dart';

class PianoPitchScreen extends StatefulWidget {
  const PianoPitchScreen({super.key});

  @override
  State<PianoPitchScreen> createState() => _PianoPitchScreenState();
}

class _PianoPitchScreenState extends State<PianoPitchScreen> with RouteAware, WidgetsBindingObserver {
  final AudioSynthService _synth = AudioSynthService();
  late final PitchService _service;
  late final PitchTracker _tracker;
  StreamSubscription<PitchFrame>? _sub;
  final ScrollController _keyboardController = ScrollController();
  static const double _keyHeight = 36;
  bool _initialScrollSet = false;
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[PianoPitchScreen] initState');
    _service = PitchService();
    _tracker = PitchTracker();
    _isVisible = true;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerKeyboardInitial();
      _start();
    });
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
  void didPopNext() {
    // Called when returning to this screen (e.g., from an exercise)
    debugPrint('[PianoPitchScreen] didPopNext - returning to Piano screen');
    _isVisible = true;
    // Ensure recording is active when returning
    if (!_service.isRunning) {
      _restartPitchDetection();
    } else {
      // Even if running, ensure the stream subscription is active
      _ensureStreamSubscription();
    }
  }

  @override
  void didPush() {
    // Called when this screen is pushed
    debugPrint('[PianoPitchScreen] didPush - Piano screen pushed');
    _isVisible = true;
    // Ensure recording starts when screen is pushed
    if (!_service.isRunning) {
      _start();
    }
  }

  void _ensureStreamSubscription() {
    if (_sub == null || _sub!.isPaused) {
      debugPrint('[PianoPitchScreen] Re-establishing stream subscription');
      _sub?.cancel();
      _sub = _service.stream.listen(
        _tracker.updateFromReading,
        onError: (error) {
          debugPrint('[PianoPitchScreen] Stream error: $error');
          _restartPitchDetection();
        },
      );
    }
  }

  @override
  void didPop() {
    // Called when leaving this screen
    debugPrint('[PianoPitchScreen] didPop - leaving Piano screen');
    _isVisible = false;
    routeObserver.unsubscribe(this);
  }

  @override
  void didPushNext() {
    // Called when navigating away from this screen
    debugPrint('[PianoPitchScreen] didPushNext - navigating away from Piano');
    _isVisible = false;
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
    } else if (state == AppLifecycleState.paused) {
      debugPrint('[PianoPitchScreen] App paused - keeping recording active');
      // Don't stop recording on pause, just keep it running
    }
  }

  Future<void> _start() async {
    if (!mounted || !_isVisible) {
      debugPrint('[PianoPitchScreen] Skipping start - not mounted or not visible');
      return;
    }
    debugPrint('[PianoPitchScreen] Starting pitch detection...');
    try {
      await _service.start();
      _sub?.cancel();
      _sub = _service.stream.listen(
        _tracker.updateFromReading,
        onError: (error) {
          debugPrint('[PianoPitchScreen] Stream error: $error');
          _restartPitchDetection();
        },
        cancelOnError: false, // Keep listening even on errors
      );
      debugPrint('[PianoPitchScreen] Pitch detection started and streaming continuously');
    } catch (e) {
      debugPrint('[PianoPitchScreen] Error starting pitch detection: $e');
      // Retry after a delay
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _isVisible) {
          _restartPitchDetection();
        }
      });
    }
  }

  Future<void> _restartPitchDetection() async {
    if (!mounted || !_isVisible) return;
    debugPrint('[PianoPitchScreen] Restarting pitch detection...');
    await _sub?.cancel();
    _sub = null;
    try {
      await _service.stop();
    } catch (e) {
      debugPrint('[PianoPitchScreen] Error stopping service: $e');
    }
    // Wait a bit longer to ensure exercise recorder is fully released
    await Future.delayed(const Duration(milliseconds: 300));
    // Force release any stuck audio session
    await AudioSessionManager.instance.forceReleaseAll();
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted && _isVisible) {
      await _start();
    }
  }

  @override
  void dispose() {
    debugPrint('[PianoPitchScreen] dispose');
    _isVisible = false;
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    _sub?.cancel();
    _service.dispose();
    _synth.stop();
    _keyboardController.dispose();
    _tracker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
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
      ),
    );
  }

  void _handleKeyTap(int midi) {
    _tracker.setManualMidi(midi);
    unawaited(_playTapTone(midi));
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

  Future<void> _playTapTone(int midi) async {
    final notes = [ReferenceNote(startSec: 0, endSec: 0.6, midi: midi)];
    final path = await _synth.renderReferenceNotes(notes);
    await _synth.playFile(path);
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

  final double _alpha = 0.25;
  final double _confidenceThreshold = 0.5;
  final Duration _holdDuration = const Duration(milliseconds: 300);
  final int _holdFrames = 2;

  DateTime? _lastValidTs;
  double? _smoothedFreq;
  double? _smoothedCents;
  int? _stableMidi;
  int? _pendingMidi;
  int _pendingCount = 0;

  String get rangeLabel => '${_noteName(rangeStartNote)}–${_noteName(rangeEndNote)}';

  void updateFromReading(PitchFrame frame) {
    final freq = frame.frequencyHz;
    final conf = frame.confidence;
    confidence = conf;

    final valid = conf >= _confidenceThreshold && freq > 0 && freq.isFinite;
    if (!valid) {
      if (_lastValidTs != null &&
          frame.ts.difference(_lastValidTs!) <= _holdDuration) {
        notifyListeners();
        return;
      }
      _clear();
      notifyListeners();
      return;
    }

    _lastValidTs = frame.ts;
    _smoothedFreq = _smooth(_smoothedFreq, freq, _alpha);
    currentFreqHz = _smoothedFreq;

    final midiRaw = 69 + 12 * (math.log(freq / 440.0) / math.ln2);
    final nearest = midiRaw.round();
    _updateStableMidi(nearest);
    currentMidi = _stableMidi;
    currentNoteName = _stableMidi == null ? null : _noteName(_stableMidi!);

    if (_stableMidi != null) {
      final rawCents = (midiRaw - _stableMidi!) * 100;
      _smoothedCents = _smooth(_smoothedCents, rawCents, _alpha);
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
    currentMidi = midi;
    currentNoteName = _noteName(midi);
    centsOff = 0.0;
    _lastValidTs = DateTime.now();
    _pendingMidi = null;
    _pendingCount = 0;
    notifyListeners();
  }

  void _updateStableMidi(int candidate) {
    if (_stableMidi == null) {
      _stableMidi = candidate;
      _pendingMidi = null;
      _pendingCount = 0;
      return;
    }
    if (candidate == _stableMidi) {
      _pendingMidi = null;
      _pendingCount = 0;
      return;
    }
    if (_pendingMidi == candidate) {
      _pendingCount += 1;
    } else {
      _pendingMidi = candidate;
      _pendingCount = 1;
    }
    if (_pendingCount >= _holdFrames) {
      _stableMidi = candidate;
      _pendingMidi = null;
      _pendingCount = 0;
      _smoothedCents = null;
    }
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
    _pendingMidi = null;
    _pendingCount = 0;
    _smoothedCents = null;
    _smoothedFreq = null;
  }

  String _noteName(int midi) {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (midi / 12).floor() - 1;
    return '${names[midi % 12]}$octave';
  }
}
