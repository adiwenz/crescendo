import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:one_clock_audio/one_clock_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';

class OneClockDebugTestScreen extends StatefulWidget {
  const OneClockDebugTestScreen({super.key});

  @override
  State<OneClockDebugTestScreen> createState() =>
      _OneClockDebugTestScreenState();
}

class _OneClockDebugTestScreenState extends State<OneClockDebugTestScreen> {
  final _offsetSamplesCtrl = TextEditingController(text: '0');

  bool _busy = false;
  bool _initialized = false;

  bool _isArmed = false; // ready to start record+play
  bool _isRunning = false; // currently recording + playing ref
  bool _hasTake = false; // have recorded audio available

  bool _muteRef = false;
  bool _muteRecording = false;

  double? _sampleRate;

  // Paths (all file paths; ref is copied from asset in bootstrap)
  String? _refPath;
  String? _vocalPath;
  String? _mixGoodPath;
  String? _mixBadPath;

  // Timestamps
  int? _playStartSample;
  int? _recStartSample;

  // Live pitch (from OneClockAudio.captureStream + pitch_detector_dart)
  PitchDetector? _pitchDetector;
  StreamSubscription<OneClockCapture>? _captureSub;
  double? _liveHz;
  double? _liveCents;
  String _liveNoteName = '';
  int _pitchFramesSeen = 0;
  final List<double> _pitchHistory = [];
  static const int _kPitchHistorySize = 5;
  static const int _kPitchBufferSize = 1024;
  final List<double> _pitchSampleBuffer = [];
  int _lastPitchUpdateMs = 0;
  static const int _kPitchUiThrottleMs = 33;
  Timer? _captureWarningTimer;
  int _captureEventCount = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _captureSub?.cancel();
    _captureSub = null;
    _captureWarningTimer?.cancel();
    _captureWarningTimer = null;
    _offsetSamplesCtrl.dispose();
    super.dispose();
  }

  void _addLog(String s) {
    final line = '[${DateTime.now().toIso8601String()}] $s';
    // ignore: avoid_print
    print('DBG_ONECLOCK $line');
  }

  void _logPlatformException(PlatformException e, StackTrace st) {
    _addLog(
        'PlatformException: code=${e.code} message=${e.message} details=${e.details}');
    _addLog(st.toString());
  }

  /// Convert PCM16 bytes (little-endian) to float samples in [-1, 1].
  static List<double> _pcm16ToDoubles(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    final out = <double>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final v = bd.getInt16(i, Endian.little);
      out.add(v / 32768.0);
    }
    return out;
  }

  /// Nearest note name and cents from Hz (A4 = 440).
  static String _hzToNoteName(double hz) {
    if (hz <= 0 || !hz.isFinite) return '';
    final midi = 69 + 12 * (math.log(hz / 440.0) / math.ln2);
    final nearest = midi.round();
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final name = names[nearest % 12];
    final octave = (nearest ~/ 12) - 1;
    return '$name$octave';
  }

  static double? _hzToCentsFromA4(double hz) {
    if (hz <= 0 || !hz.isFinite) return null;
    final midi = 69 + 12 * (math.log(hz / 440.0) / math.ln2);
    final nearest = midi.round();
    return (midi - nearest) * 100;
  }

  /// Clears pitch state and warning timer. Does not cancel the capture subscription
  /// (subscription is long-lived so native eventSink is set before first recording).
  void _clearPitchState() {
    _captureWarningTimer?.cancel();
    _captureWarningTimer = null;
    _pitchSampleBuffer.clear();
    _pitchHistory.clear();
    _liveHz = null;
    _liveCents = null;
    _liveNoteName = '';
  }

  void _onCaptureEvent(OneClockCapture cap) async {
    _captureEventCount++;
    _captureWarningTimer?.cancel();
    _captureWarningTimer = null;

    if (cap.pcm16.isEmpty) return;
    final samples = _pcm16ToDoubles(cap.pcm16);
    _pitchSampleBuffer.addAll(samples);
    while (_pitchSampleBuffer.length >= _kPitchBufferSize && _pitchDetector != null) {
      final window = List<double>.from(_pitchSampleBuffer.sublist(0, _kPitchBufferSize));
      _pitchSampleBuffer.removeRange(0, _kPitchBufferSize);
      try {
        final res = await _pitchDetector!.getPitchFromFloatBuffer(window);
        _pitchFramesSeen++;
        if (res.pitched && res.pitch.isFinite && res.pitch > 0) {
          final hz = res.pitch;
          _pitchHistory.add(hz);
          if (_pitchHistory.length > _kPitchHistorySize) _pitchHistory.removeAt(0);
          final smoothed = _pitchHistory.length == 0
              ? hz
              : _pitchHistory.reduce((a, b) => a + b) / _pitchHistory.length;
          _liveHz = smoothed;
          _liveCents = _hzToCentsFromA4(smoothed);
          _liveNoteName = _hzToNoteName(smoothed);
        } else {
          _liveHz = null;
          _liveCents = null;
          _liveNoteName = '';
        }
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - _lastPitchUpdateMs > _kPitchUiThrottleMs) {
          _lastPitchUpdateMs = nowMs;
          if (mounted) setState(() {});
        }
        if (_pitchFramesSeen % 30 == 0 && _pitchFramesSeen > 0) {
          _addLog('pitch hz=${_liveHz?.toStringAsFixed(1) ?? "—"} frames=$_pitchFramesSeen');
        }
      } catch (_) {
        _liveHz = null;
        _liveCents = null;
        _liveNoteName = '';
      }
    }
  }

  Future<void> _prepareNewRunPaths() async {
    final tempDir = await getTemporaryDirectory();
    final base = Directory('${tempDir.path}/one_clock_debug');
    if (!await base.exists()) await base.create(recursive: true);

    final runId = DateTime.now().millisecondsSinceEpoch;

    _vocalPath = '${base.path}/vocal_$runId.wav';
    _mixGoodPath = '${base.path}/mix_good_$runId.wav';
    _mixBadPath = '${base.path}/mix_bad_$runId.wav';

    _addLog('NEW RUN runId=$runId');
    _addLog('vocal=$_vocalPath');
    _addLog('mixGood=$_mixGoodPath');
    _addLog('mixBad=$_mixBadPath');
  }

  Future<void> _bootstrap() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _addLog('ensureStarted()…');
      try {
        await OneClockAudio.ensureStarted();
      } on PlatformException catch (e, st) {
        _logPlatformException(e, st);
        rethrow;
      }

      _addLog('getSampleRate()…');
      try {
        final sr = await OneClockAudio.getSampleRate();
        _sampleRate = sr;
      } on PlatformException catch (e, st) {
        _logPlatformException(e, st);
        rethrow;
      }
      _addLog('sampleRate=$_sampleRate');

      if (_sampleRate != null && _sampleRate! > 0) {
        _pitchDetector = PitchDetector(
          audioSampleRate: _sampleRate!.toDouble(),
          bufferSize: _kPitchBufferSize,
        );
      }

      final tempDir = await getTemporaryDirectory();
      final base = Directory('${tempDir.path}/one_clock_debug');
      if (!await base.exists()) await base.create(recursive: true);

      // Copy reference asset to a file path (OneClockAudio expects file paths)
      const refAsset = 'assets/audio/reference.wav';
      final refFile = File('${base.path}/ref_reference.wav');
      try {
        final bytes = await rootBundle.load(refAsset);
        await refFile.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      } catch (e, st) {
        _addLog('Failed to copy ref asset: $e');
        _addLog(st.toString());
        throw StateError('Could not prepare reference file. Is $refAsset in pubspec?');
      }
      _refPath = refFile.path;
      _addLog('ref path=$_refPath');

      _initialized = true;
      _isArmed = true;
      // Subscribe once so native eventSink is set before first recording (avoids delay before startRecording).
      _captureSub?.cancel();
      _captureSub = OneClockAudio.captureStream.listen(_onCaptureEvent);
      _addLog('Initialized. Ready. Tap "Record + Play Ref".');
    } on PlatformException catch (e, st) {
      _logPlatformException(e, st);
    } catch (e, st) {
      _addLog('BOOTSTRAP ERROR: $e');
      _addLog(st.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _safeStopAll() async {
    _clearPitchState();
    try {
      _addLog('stopAll()…');
      await OneClockAudio.stopAll();
    } on PlatformException catch (e, st) {
      _addLog('stopAll PlatformException: code=${e.code} message=${e.message} details=${e.details}');
      _addLog(st.toString());
    } catch (e, st) {
      _addLog('stopAll ERROR: $e');
      _addLog(st.toString());
    }
  }

  Future<void> _recordAndPlayRef() async {
    if (!_initialized || _busy) return;
    if (_refPath == null) {
      _addLog('ERROR: Missing ref path. ref=$_refPath');
      return;
    }

    setState(() => _busy = true);
    try {
      _hasTake = false;
      _playStartSample = null;
      _recStartSample = null;

      await _safeStopAll();

      await _prepareNewRunPaths();

      if (_vocalPath != null) {
        final vf = File(_vocalPath!);
        final existsBefore = await vf.exists();
        final sizeBefore = existsBefore ? await vf.length() : 0;
        _addLog('vocal exists(before)=$existsBefore size(before)=$sizeBefore');
      }

      _addLog('START: startRecording + startPlayback (Record + Play Ref)');
      _isRunning = true;
      _isArmed = false;
      setState(() {});

      _clearPitchState();
      _captureEventCount = 0;
      _pitchFramesSeen = 0;
      _captureWarningTimer = Timer(const Duration(seconds: 1), () {
        if (!mounted) return;
        if (_captureEventCount == 0) {
          _addLog(
              'WARNING: No capture events after 1s. If captureStream does not emit during startRecording, modify native transport tap to also send events.');
        }
      });

      try {
        await OneClockAudio.startRecording(outputPath: _vocalPath!);
      } on PlatformException catch (e, st) {
        _logPlatformException(e, st);
        rethrow;
      }
      try {
        await OneClockAudio.startPlayback(referencePath: _refPath!, gain: 1.0);
      } on PlatformException catch (e, st) {
        _logPlatformException(e, st);
        rethrow;
      }

      try {
        _playStartSample = await OneClockAudio.getPlaybackStartSampleTime();
        _addLog('playStartSample=$_playStartSample');
      } on PlatformException catch (e, st) {
        _addLog('getPlaybackStartSampleTime: ${e.code} ${e.message}');
        _addLog(st.toString());
      }
      try {
        _recStartSample = await OneClockAudio.getRecordStartSampleTime();
        _addLog('recStartSample=$_recStartSample');
      } on PlatformException catch (e, st) {
        _addLog('getRecordStartSampleTime: ${e.code} ${e.message}');
        _addLog(st.toString());
      }

      _addLog('Recording+Playback running. Press STOP when done.');
    } on PlatformException catch (e, st) {
      _logPlatformException(e, st);
      _clearPitchState();
      await _safeStopAll();
      _isRunning = false;
      _isArmed = true;
    } catch (e, st) {
      _addLog('START FLOW ERROR: $e');
      _addLog(st.toString());
      _clearPitchState();
      await _safeStopAll();
      _isRunning = false;
      _isArmed = true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopTake() async {
    if (!_initialized || _busy) return;

    _clearPitchState();
    setState(() => _busy = true);
    try {
      _addLog('STOP: stopRecording() + stopAll()');
      try {
        await OneClockAudio.stopRecording();
      } on PlatformException catch (e, st) {
        _addLog('stopRecording: ${e.code} ${e.message}');
        _addLog(st.toString());
      }
      await _safeStopAll();

      _isRunning = false;
      _isArmed = true;
      _hasTake = true;

      final vocalFile = File(_vocalPath!);
      final vocalExists = await vocalFile.exists();
      final vocalSize = vocalExists ? await vocalFile.length() : 0;
      _addLog('vocal exists=$vocalExists size=$vocalSize path=$_vocalPath');
      if (!vocalExists || vocalSize < 1024) {
        _addLog(
            'WARNING: vocal file missing or tiny. Mix will be blocked until you have a valid take.');
      }
    } on PlatformException catch (e, st) {
      _addLog('stopTake PlatformException: ${e.code} ${e.message}');
      _addLog(st.toString());
    } catch (e, st) {
      _addLog('STOP FLOW ERROR: $e');
      _addLog(st.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int _parseOffsetSamples() {
    final raw = _offsetSamplesCtrl.text.trim();
    return int.tryParse(raw) ?? 0;
  }

  double? _offsetMsFromSamples(int samples) {
    final sr = _sampleRate;
    if (sr == null || sr <= 0) return null;
    return (samples / sr) * 1000.0;
  }

  Future<void> _playRefAndRecording() async {
    if (!_initialized || _busy) return;
    if (_refPath == null || _vocalPath == null) {
      _addLog('Play blocked: need ref and recording. Record a take first.');
      return;
    }

    setState(() => _busy = true);
    try {
      await _safeStopAll();
      final offsetSamples = _parseOffsetSamples();
      _addLog('Play ref + recording (offset=$offsetSamples)');
      try {
        await OneClockAudio.loadReference(_refPath!);
        await OneClockAudio.loadVocal(_vocalPath!);
        await OneClockAudio.setVocalOffset(offsetSamples);
        await OneClockAudio.setTrackGains(
          ref: _muteRef ? 0.0 : 1.0,
          voc: _muteRecording ? 0.0 : 1.0,
        );
        await OneClockAudio.startPlaybackTwoTrack();
      } on PlatformException catch (e, st) {
        _logPlatformException(e, st);
      }
    } catch (e, st) {
      _addLog('Play ref + recording error: $e');
      _addLog(st.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateTrackGains() async {
    try {
      await OneClockAudio.setTrackGains(
        ref: _muteRef ? 0.0 : 1.0,
        voc: _muteRecording ? 0.0 : 1.0,
      );
    } on PlatformException catch (e, st) {
      _logPlatformException(e, st);
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    _clearPitchState();
    setState(() => _busy = true);
    try {
      await _safeStopAll();
      await _prepareNewRunPaths();
      _isRunning = false;
      _isArmed = _initialized;
      _hasTake = false;
      _playStartSample = null;
      _recStartSample = null;
      _addLog('Reset done.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offsetSamples = _parseOffsetSamples();
    final offsetMs = _offsetMsFromSamples(offsetSamples);

    return Scaffold(
      appBar: AppBar(
        title: const Text('OneClock Debug Test'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _reset,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildLivePitchDisplay(),
            _buildStatusCard(offsetSamples, offsetMs),
            const SizedBox(height: 8),
            _buildControls(),
            const Divider(height: 16),
            Expanded(child: _buildLog()),
          ],
        ),
      ),
    );
  }

  Widget _buildLivePitchDisplay() {
    final note = _liveNoteName.isNotEmpty ? _liveNoteName : '—';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Live pitch',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            note,
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
          ),
          if (_liveHz != null && _liveHz! > 0)
            Text(
              '${_liveHz!.toStringAsFixed(1)} Hz${_liveCents != null ? '  ${_liveCents!.toStringAsFixed(0)}¢' : ''}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(int offsetSamples, double? offsetMs) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'initialized=$_initialized busy=$_busy armed=$_isArmed running=$_isRunning hasTake=$_hasTake'),
              const SizedBox(height: 8),
              Text(
                  'sampleRate=${_sampleRate?.toStringAsFixed(2) ?? 'unknown'}'),
              Text('playStartSample=${_playStartSample ?? 'n/a'}'),
              Text('recStartSample=${_recStartSample ?? 'n/a'}'),
              const SizedBox(height: 4),
              Text(
                'Live pitch: ${_liveHz?.toStringAsFixed(1) ?? '—'} Hz${_liveNoteName.isNotEmpty ? ' ($_liveNoteName${_liveCents != null ? ', ${_liveCents!.toStringAsFixed(0)}¢' : ''})' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Offset (samples): '),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _offsetSamplesCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                      '≈ ${offsetMs == null ? 'n/a' : offsetMs.toStringAsFixed(2)} ms'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          ElevatedButton.icon(
            onPressed: (!_initialized || _busy || !_isArmed)
                ? null
                : _recordAndPlayRef,
            icon: const Icon(Icons.fiber_manual_record),
            label: const Text('Record + Play Ref'),
          ),
          ElevatedButton.icon(
            onPressed:
                (!_initialized || _busy || !_isRunning) ? null : _stopTake,
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
          ),
          ElevatedButton.icon(
            onPressed: (!_initialized || _busy || !_hasTake)
                ? null
                : _playRefAndRecording,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Play ref + recording'),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MuteChip(
                label: 'Ref',
                muted: _muteRef,
                onPressed: () {
                  setState(() => _muteRef = !_muteRef);
                  _updateTrackGains();
                },
              ),
              const SizedBox(width: 8),
              _MuteChip(
                label: 'Recording',
                muted: _muteRecording,
                onPressed: () {
                  setState(() => _muteRecording = !_muteRecording);
                  _updateTrackGains();
                },
              ),
            ],
          ),
          TextButton.icon(
            onPressed: (!_initialized || _busy) ? null : _safeStopAll,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Stop All'),
          ),
        ],
      ),
    );
  }

  Widget _buildLog() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Logs go to terminal (Run console).',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

class _MuteChip extends StatelessWidget {
  final String label;
  final bool muted;
  final VoidCallback onPressed;

  const _MuteChip({
    required this.label,
    required this.muted,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            muted ? Icons.volume_off : Icons.volume_up,
            size: 18,
            color: muted
                ? Theme.of(context).colorScheme.onSecondaryContainer
                : null,
          ),
          const SizedBox(width: 6),
          Text('Mute $label'),
        ],
      ),
      selected: muted,
      onSelected: (_) => onPressed(),
    );
  }
}
