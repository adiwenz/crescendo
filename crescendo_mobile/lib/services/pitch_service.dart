import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/pitch_frame.dart' as recording;
import '../utils/audio_constants.dart';
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
  static PitchService? _instance;
  static PitchService get instance {
    _instance ??= PitchService();
    return _instance!;
  }

  final RecordingService _recording;
  final StreamController<PitchFrame> _controller =
      StreamController<PitchFrame>.broadcast();
  StreamSubscription<recording.PitchFrame>? _sub;
  bool _running = false;
  bool _disposed = false;
  bool _pausedByPlayback = false;
  DateTime? _watchdogDisabledUntil;
  DateTime? _lastFrameTime;
  Timer? _watchdogTimer;

  PitchService({RecordingService? recording})
      : _recording = recording ?? RecordingService(
          owner: 'piano',
          sampleRate: AudioConstants.audioSampleRate,
          bufferSize: 1024, // Smaller buffer for lower latency (~21ms at 48kHz)
        );

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
          
          // Compute confidence based on pitch validity and voiced probability
          // Use voicedProb if available, otherwise use heuristic
          double confidence = 0.0;
          final hzValue = hasPitch ? hz : null;
          if (hzValue != null) {
            // If voicedProb is available, use it; otherwise use a heuristic
            if (frame.voicedProb != null && frame.voicedProb! > 0) {
              confidence = frame.voicedProb!.clamp(0.0, 1.0);
            } else {
              // Heuristic: assume good confidence if pitch is detected and in reasonable range
              // Typical singing range: 80-1000 Hz
              if (hzValue >= 80 && hzValue <= 1000) {
                confidence = 0.85; // Good confidence for typical singing range
              } else if (hzValue >= 50 && hzValue < 80) {
                confidence = 0.70; // Lower confidence for very low notes
              } else if (hzValue > 1000 && hzValue <= 2000) {
                confidence = 0.75; // Lower confidence for very high notes
              } else {
                confidence = 0.50; // Low confidence for out-of-range
              }
            }
          }
          
          _controller.add(PitchFrame(
            frequencyHz: hzValue ?? 0,
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
      if (!_running || _disposed || _pausedByPlayback) {
        timer.cancel();
        return;
      }
      
      // Check if watchdog is temporarily disabled (e.g., during MIDI playback)
      if (_watchdogDisabledUntil != null) {
        final now = DateTime.now();
        if (now.isBefore(_watchdogDisabledUntil!)) {
          return; // Watchdog disabled, don't check
        } else {
          _watchdogDisabledUntil = null; // Re-enable
        }
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
  
  /// Temporarily disable watchdog for a duration (e.g., during MIDI playback)
  void disableWatchdogTemporarily({Duration duration = const Duration(seconds: 5)}) {
    _watchdogDisabledUntil = DateTime.now().add(duration);
    debugPrint('[PitchService] Watchdog disabled for ${duration.inSeconds}s (until ${_watchdogDisabledUntil})');
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

  /// Pause pitch detection for MIDI playback
  /// Stops watchdog, stops recording, and sets pause flag
  Future<void> pauseForPlayback() async {
    if (!_running || _pausedByPlayback) return;
    
    debugPrint('[PitchService] paused mic');
    _pausedByPlayback = true;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    
    // Disable watchdog for 5 seconds to prevent restart during MIDI playback
    disableWatchdogTemporarily(duration: const Duration(seconds: 5));
    
    await _sub?.cancel();
    _sub = null;
    
    try {
      await _recording.stop();
    } catch (e) {
      debugPrint('[PitchService] Error stopping recording for playback: $e');
    }
  }
  
  /// Pause mic, play MIDI notes, then resume mic when playback completes
  /// This ensures mic doesn't restart during MIDI playback
  Future<void> pauseForMidiPlaybackAndPlay(
    Future<void> Function() playMidiNotes,
  ) async {
    if (!_running || _pausedByPlayback) {
      // If not running, just play MIDI without pause/resume
      await playMidiNotes();
      return;
    }
    
    // Pause mic
    await pauseForPlayback();
    
    try {
      // Play MIDI and wait for completion
      debugPrint('[PitchService] midi started');
      await playMidiNotes();
      debugPrint('[PitchService] midi done, resuming mic');
      
      // Resume mic
      await resumeAfterPlayback();
    } catch (e) {
      // If playback fails, still try to resume mic
      debugPrint('[PitchService] MIDI playback error: $e, resuming mic');
      await resumeAfterPlayback();
      rethrow;
    }
  }

  /// Resume pitch detection after MIDI playback
  /// Restarts recording and detection, re-enables watchdog
  Future<void> resumeAfterPlayback({Duration delay = Duration.zero}) async {
    if (!_pausedByPlayback) return;
    
    if (delay.inMilliseconds > 0) {
      await Future.delayed(delay);
    }
    
    if (_disposed || !_pausedByPlayback) return;
    
    _pausedByPlayback = false;
    
    if (!_running) {
      // Was not running before pause, nothing to resume
      return;
    }
    
    // Restart recording and subscription
    try {
      await _recording.start();
      _lastFrameTime = DateTime.now();
      
      _sub = _recording.liveStream.listen(
        (frame) {
          _lastFrameTime = DateTime.now();
          final hz = frame.hz;
          final hasPitch = hz != null && hz > 0 && hz.isFinite;
          
          // Compute confidence based on pitch validity and voiced probability
          double confidence = 0.0;
          final hzValue = hasPitch ? hz : null;
          if (hzValue != null) {
            if (frame.voicedProb != null && frame.voicedProb! > 0) {
              confidence = frame.voicedProb!.clamp(0.0, 1.0);
            } else {
              if (hzValue >= 80 && hzValue <= 1000) {
                confidence = 0.85;
              } else if (hzValue >= 50 && hzValue < 80) {
                confidence = 0.70;
              } else if (hzValue > 1000 && hzValue <= 2000) {
                confidence = 0.75;
              } else {
                confidence = 0.50;
              }
            }
          }
          
          _controller.add(PitchFrame(
            frequencyHz: hzValue ?? 0,
            confidence: confidence,
            ts: DateTime.now(),
          ));
        },
        onError: (error) {
          debugPrint('[PitchService] Stream error: $error');
          _handleStreamError();
        },
        cancelOnError: false,
      );
      
      _startWatchdog();
    } catch (e) {
      debugPrint('[PitchService] Error resuming after playback: $e');
      _running = false;
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
