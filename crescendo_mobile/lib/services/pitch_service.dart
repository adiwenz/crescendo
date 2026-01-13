import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/pitch_frame.dart' as recording;
import 'recording_service.dart';

class PitchFrame {
  final double frequencyHz;
  final double confidence;
  final DateTime ts;

  const PitchFrame({
    required this.frequencyHz,
    required this.confidence,
    required this.ts,
  });
}

class PitchService {
  final RecordingService _recording;
  final StreamController<PitchFrame> _controller =
      StreamController<PitchFrame>.broadcast();
  StreamSubscription<recording.PitchFrame>? _sub;
  bool _running = false;
  bool _disposed = false;
  DateTime? _lastFrameTime;
  Timer? _watchdogTimer;

  PitchService({RecordingService? recording})
      : _recording = recording ?? RecordingService();

  Stream<PitchFrame> get stream => _controller.stream;
  bool get isRunning => _running;

  Future<void> start() async {
    if (_disposed) {
      debugPrint('[PitchService] Cannot start: already disposed');
      return;
    }
    if (_running) {
      debugPrint('[PitchService] Already running, skipping start');
      return;
    }

    try {
      debugPrint('[PitchService] Starting pitch detection...');
      // Force stop any existing recording first to release resources
      try {
        await _recording.stop();
      } catch (e) {
        debugPrint('[PitchService] Error stopping existing recording: $e');
      }

      await _recording.start();
      _running = true;
      _lastFrameTime = DateTime.now();
      
      _sub = _recording.liveStream.listen(
        (frame) {
          _lastFrameTime = DateTime.now();
          final hz = frame.hz;
          final hasPitch = hz != null && hz > 0 && hz.isFinite;
          // TODO: Replace with real confidence from detector when available.
          final confidence = hasPitch ? 1.0 : 0.0;
          _controller.add(PitchFrame(
            frequencyHz: hasPitch ? hz : 0,
            confidence: confidence,
            ts: DateTime.now(),
          ));
        },
        onError: (error) {
          debugPrint('[PitchService] Stream error: $error');
          // Auto-restart on error
          _handleStreamError();
        },
        cancelOnError: false,
      );

      // Start watchdog timer to detect stuck state
      _startWatchdog();
      debugPrint('[PitchService] Pitch detection started successfully');
    } catch (e) {
      debugPrint('[PitchService] Error starting: $e');
      _running = false;
      // Retry once after a delay
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!_disposed && !_running) {
          debugPrint('[PitchService] Retrying start after error...');
          start();
        }
      });
      rethrow;
    }
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_running || _disposed) {
        timer.cancel();
        return;
      }
      
      final now = DateTime.now();
      if (_lastFrameTime != null) {
        final timeSinceLastFrame = now.difference(_lastFrameTime!);
        if (timeSinceLastFrame.inSeconds > 2) {
          debugPrint('[PitchService] WATCHDOG: No frames for ${timeSinceLastFrame.inSeconds}s, restarting...');
          _handleStreamError();
        }
      } else if (_running) {
        // Started but no frames yet - give it a bit more time
        final timeSinceStart = now.difference(_lastFrameTime ?? now);
        if (timeSinceStart.inSeconds > 3) {
          debugPrint('[PitchService] WATCHDOG: No frames after start, restarting...');
          _handleStreamError();
        }
      }
    });
  }

  Future<void> _handleStreamError() async {
    if (_disposed) return;
    debugPrint('[PitchService] Handling stream error, restarting...');
    _watchdogTimer?.cancel();
    await _sub?.cancel();
    _sub = null;
    _running = false;
    
    // Force stop and dispose the recorder
    try {
      await _recording.stop();
    } catch (e) {
      debugPrint('[PitchService] Error stopping recorder: $e');
    }
    
    // Wait a bit before retrying
    await Future.delayed(const Duration(milliseconds: 300));
    
    if (!_disposed) {
      await start();
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    debugPrint('[PitchService] Stopping pitch detection...');
    _running = false;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    await _sub?.cancel();
    _sub = null;
    try {
      await _recording.stop();
      debugPrint('[PitchService] Pitch detection stopped');
    } catch (e) {
      debugPrint('[PitchService] Error stopping recording: $e');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    debugPrint('[PitchService] Disposing...');
    _disposed = true;
    await stop();
    await _controller.close();
    try {
      await _recording.dispose();
    } catch (e) {
      debugPrint('[PitchService] Error disposing recording: $e');
    }
    debugPrint('[PitchService] Disposed');
  }
}
