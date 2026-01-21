import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_headset_detector/flutter_headset_detector.dart';

/// Audio output route types
enum AudioOutputType {
  speaker,
  headphones,
  bluetooth,
  unknown,
}

/// Service that wraps flutter_headset_detector for detecting audio route changes
/// This is the single source of truth for audio route detection
class AudioRouteService {
  static final AudioRouteService _instance = AudioRouteService._internal();
  factory AudioRouteService() => _instance;
  AudioRouteService._internal();

  HeadsetDetector? _detector;
  AudioOutputType _currentOutput = AudioOutputType.unknown;
  final StreamController<AudioOutputType> _outputController =
      StreamController<AudioOutputType>.broadcast();

  /// Current audio output type
  AudioOutputType get currentOutput => _currentOutput;

  /// Stream of audio output changes
  Stream<AudioOutputType> get outputStream => _outputController.stream;

  /// Initialize the service and start listening to route changes
  Future<void> initialize() async {
    if (_detector != null) {
      // Already initialized
      if (kDebugMode) {
        debugPrint(
            '[AudioRoute] ⚠️ Already initialized, skipping (detector=$_detector)');
      }
      return;
    }

    try {
      if (kDebugMode) {
        debugPrint('[AudioRoute] Creating HeadsetDetector instance...');
      }
      _detector = HeadsetDetector();

      if (kDebugMode) {
        debugPrint('[AudioRoute] HeadsetDetector created: $_detector');
        debugPrint('[AudioRoute] Getting initial state...');
        debugPrint('');
        debugPrint('');
        debugPrint('');
      }

      // Get initial state (returns Map<HeadsetType, HeadsetState>)
      final initialState = await _detector!.getCurrentState;
      _currentOutput = _mapToOutputType(initialState);

      debugPrint('Got here ⚠️');

      if (kDebugMode) {
        final wiredState =
            initialState[HeadsetType.WIRED] ?? HeadsetState.DISCONNECTED;
        final wirelessState =
            initialState[HeadsetType.WIRELESS] ?? HeadsetState.DISCONNECTED;
        debugPrint(
            '[AudioRoute] Initial state: wired=${wiredState == HeadsetState.CONNECTED ? "CONNECTED" : "DISCONNECTED"}, wireless=${wirelessState == HeadsetState.CONNECTED ? "CONNECTED" : "DISCONNECTED"}');
        debugPrint('[AudioRoute] Initial output: $_currentOutput');
      }

      // Listen to route changes
      if (kDebugMode) {
        debugPrint('[AudioRoute] Setting up event listener...');
      }

      _detector!.setListener((HeadsetChangedEvent event) {
        // CRITICAL: Log immediately when ANY event is received
        if (kDebugMode) {
          debugPrint(
              '[AudioRoute] ⚡ EVENT RECEIVED: $event (type: ${event.runtimeType})');
        }

        // Log specific headphone plug/unplug events
        if (kDebugMode) {
          switch (event) {
            case HeadsetChangedEvent.WIRED_CONNECTED:
              debugPrint('[AudioRoute] 🎧 WIRED HEADPHONES PLUGGED IN');
              break;
            case HeadsetChangedEvent.WIRED_DISCONNECTED:
              debugPrint('[AudioRoute] 🎧 WIRED HEADPHONES UNPLUGGED');
              break;
            case HeadsetChangedEvent.WIRELESS_CONNECTED:
              debugPrint('[AudioRoute] 🎧 BLUETOOTH HEADPHONES CONNECTED');
              break;
            case HeadsetChangedEvent.WIRELESS_DISCONNECTED:
              debugPrint('[AudioRoute] 🎧 BLUETOOTH HEADPHONES DISCONNECTED');
              break;
          }
        }

        final newOutput = _eventToOutputType(event);

        if (kDebugMode) {
          debugPrint(
              '[AudioRoute] Output changed: $_currentOutput → $newOutput');
        }

        _currentOutput = newOutput;
        _outputController.add(newOutput);

        // For disconnect events, verify current state asynchronously to handle edge cases
        // (e.g., if both were connected and one disconnects)
        if (event == HeadsetChangedEvent.WIRED_DISCONNECTED ||
            event == HeadsetChangedEvent.WIRELESS_DISCONNECTED) {
          _verifyCurrentState();
        }
      });

      if (kDebugMode) {
        debugPrint(
            '[AudioRoute] ✅ Service initialized, listener set up and ready');
        debugPrint('[AudioRoute] Detector instance: $_detector');
        debugPrint('[AudioRoute] Waiting for headphone plug/unplug events...');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioRoute] Error initializing: $e');
      }
    }
  }

  /// Convert Map<HeadsetType, HeadsetState> to AudioOutputType
  AudioOutputType _mapToOutputType(Map<HeadsetType, HeadsetState> stateMap) {
    final wiredState = stateMap[HeadsetType.WIRED] ?? HeadsetState.DISCONNECTED;
    final wirelessState =
        stateMap[HeadsetType.WIRELESS] ?? HeadsetState.DISCONNECTED;

    if (wirelessState == HeadsetState.CONNECTED) {
      return AudioOutputType.bluetooth;
    } else if (wiredState == HeadsetState.CONNECTED) {
      return AudioOutputType.headphones;
    } else {
      return AudioOutputType.speaker;
    }
  }

  /// Convert HeadsetChangedEvent to AudioOutputType
  AudioOutputType _eventToOutputType(HeadsetChangedEvent event) {
    switch (event) {
      case HeadsetChangedEvent.WIRED_CONNECTED:
        return AudioOutputType.headphones;
      case HeadsetChangedEvent.WIRED_DISCONNECTED:
        // If wireless was connected, it should still be (we'll verify async)
        // Otherwise, assume speaker
        return _currentOutput == AudioOutputType.bluetooth
            ? AudioOutputType.bluetooth
            : AudioOutputType.speaker;
      case HeadsetChangedEvent.WIRELESS_CONNECTED:
        return AudioOutputType.bluetooth;
      case HeadsetChangedEvent.WIRELESS_DISCONNECTED:
        // If wired was connected, it should still be (we'll verify async)
        // Otherwise, assume speaker
        return _currentOutput == AudioOutputType.headphones
            ? AudioOutputType.headphones
            : AudioOutputType.speaker;
    }
  }

  /// Verify current state asynchronously (for edge cases)
  void _verifyCurrentState() {
    _detector?.getCurrentState.then((stateMap) {
      final wiredState =
          stateMap[HeadsetType.WIRED] ?? HeadsetState.DISCONNECTED;
      final wirelessState =
          stateMap[HeadsetType.WIRELESS] ?? HeadsetState.DISCONNECTED;
      final verifiedOutput = _mapToOutputType(stateMap);

      if (kDebugMode) {
        debugPrint(
            '[AudioRoute] State verification: wired=${wiredState == HeadsetState.CONNECTED ? "CONNECTED" : "DISCONNECTED"}, wireless=${wirelessState == HeadsetState.CONNECTED ? "CONNECTED" : "DISCONNECTED"}');
      }

      if (verifiedOutput != _currentOutput) {
        if (kDebugMode) {
          debugPrint(
              '[AudioRoute] State verification: updating output from $_currentOutput to $verifiedOutput');
        }
        _currentOutput = verifiedOutput;
        _outputController.add(verifiedOutput);
      }
    }).catchError((e) {
      if (kDebugMode) {
        debugPrint('[AudioRoute] Error verifying state: $e');
      }
    });
  }

  /// Check if headphones (wired or Bluetooth) are connected
  bool get hasHeadphones =>
      _currentOutput == AudioOutputType.headphones ||
      _currentOutput == AudioOutputType.bluetooth;

  /// Dispose the service
  void dispose() {
    if (kDebugMode) {
      debugPrint('[AudioRoute] Disposing service...');
    }
    _detector?.removeListener();
    if (kDebugMode) {
      debugPrint('[AudioRoute] Listener removed');
    }
    _detector = null;
    _outputController.close();
    if (kDebugMode) {
      debugPrint('[AudioRoute] Service disposed');
    }
  }

  /// Test if listener is still active by checking current state
  Future<void> testListener() async {
    if (kDebugMode) {
      debugPrint('[AudioRoute] Testing listener - checking current state...');
      debugPrint('[AudioRoute] Detector instance: $_detector');
    }
    try {
      final state = await _detector?.getCurrentState;
      if (kDebugMode) {
        debugPrint('[AudioRoute] Current state check successful: $state');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioRoute] ERROR testing listener: $e');
      }
    }
  }
}
