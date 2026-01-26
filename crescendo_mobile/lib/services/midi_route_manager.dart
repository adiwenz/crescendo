import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:audio_session/audio_session.dart';
import 'package:flutter_headset_detector/flutter_headset_detector.dart';
import '../audio/reference_midi_synth.dart';

/// Manages MIDI audio routing and recovers from headset plug/unplug events.
/// 
/// This manager ensures that MIDI playback cleanly recovers when headphones are connected
/// or disconnected, preventing hanging notes and ensuring audio is routed correctly.
class MidiRouteManager {
  static final MidiRouteManager instance = MidiRouteManager._internal();
  factory MidiRouteManager() => instance;
  MidiRouteManager._internal();

  final ReferenceMidiSynth _synth = ReferenceMidiSynth.instance;
  
  StreamSubscription<HeadsetChangedEvent>? _headsetSubscription;
  StreamSubscription<void>? _noisySubscription;
  
  bool _isResetting = false;
  Timer? _debounceTimer;

  /// Initialize the route manager.
  Future<void> init() async {
    debugPrint('[MidiRouteManager] Initializing...');
    
    // Configure audio session
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions: 
          AVAudioSessionCategoryOptions.mixWithOthers |
          AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
    ));
    
    // Subscribe to headset events
    final detector = HeadsetDetector();
    _headsetSubscription?.cancel();
    detector.setListener((event) {
      debugPrint('[MidiRouteManager] Headset event: $event');
      _triggerReset();
    });

    // Android: becomingNoisyEventStream (user unplugged headphones)
    if (Platform.isAndroid) {
      _noisySubscription?.cancel();
      _noisySubscription = session.becomingNoisyEventStream.listen((_) {
        debugPrint('[MidiRouteManager] Android Noisy event');
        _triggerReset();
      });
    }

    debugPrint('[MidiRouteManager] Initialized');
  }

  /// Dispose subscriptions.
  void dispose() {
    debugPrint('[MidiRouteManager] Disposing...');
    _headsetSubscription?.cancel();
    _noisySubscription?.cancel();
    _debounceTimer?.cancel();
  }

  void _triggerReset() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 150), () {
      resetRoute();
    });
  }

  /// Force a robust MIDI route reset.
  Future<void> resetRoute() async {
    if (_isResetting) {
      debugPrint('[MidiRouteManager] Reset already in progress, skipping');
      return;
    }
    
    _isResetting = true;
    debugPrint('[MidiRouteManager] Starting resetRoute sequence...');
    
    try {
      // Step A: MIDI Panic immediately
      debugPrint('[MidiRouteManager] Panic: Stopping all notes');
      for (int i = 0; i <= 127; i++) {
        _synth.stopNote(i); // Assuming ReferenceMidiSynth has stopNote or we add it
      }
      // Or use a batch stop if available
      await _synth.stop();

      // Step B: Force route rebind
      debugPrint('[MidiRouteManager] Toggling AudioSession...');
      final session = await AudioSession.instance;
      await session.setActive(false);
      await Future.delayed(const Duration(milliseconds: 100));
      await session.setActive(true);

      // Step C: Re-init MIDI synth
      debugPrint('[MidiRouteManager] Re-initializing MIDI synth...');
      await _synth.init(force: true); // Force reload soundfont
      
      debugPrint('[MidiRouteManager] resetRoute() complete');
    } catch (e) {
      debugPrint('[MidiRouteManager] resetRoute() FAILED: $e');
    } finally {
      _isResetting = false;
    }
  }
}
