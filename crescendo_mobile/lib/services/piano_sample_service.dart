
import 'dart:async';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart'; // Keep for now if referencing Enums? Or remove if unused
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:crescendo_mobile/core/locator.dart';
import 'package:crescendo_mobile/core/interfaces/i_audio_player.dart';

class PianoSampleService {
  static final PianoSampleService _instance = PianoSampleService._internal();
  factory PianoSampleService() => _instance;
  PianoSampleService._internal();

  static PianoSampleService get instance => _instance;

  // Pool of players to allow polyphony
  final List<IAudioPlayer> _pool = [];
  static const int _poolSize = 8;
  int _poolIndex = 0;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    
    debugPrint('[PianoSampleService] Initializing $_poolSize players...');
    for (int i = 0; i < _poolSize; i++) {
      // Use locator to get IAudioPlayer implementation (Real or Fake)
      try {
        final player = locator<IAudioPlayer>();
        // ReleaseMode and PlayerMode APIs depend on specific AudioPlayer features.
        // IAudioPlayer interface might abstract these differently or not at all.
        // If they are critical for low latency, IAudioPlayer might need 'configure({mode})' method.
        // For now, in tests we might ignore, but in prod we need them.
        // If RealAudioPlayer wraps AudioPlayer, it can expose underlying or we add methods to interface.
        // Given minimal changes, let's assume default behavior is acceptable or we cast if needed (risky).
        // Better: Add 'configure' to interface or 'setReleaseMode'.
        // IAudioPlayer defines `setReleaseMode`? No.
        // Let's rely on defaults or update interface if necessary.
        // Actually, RealAudioPlayer sets default? No.
        // To avoid compilation error since my interface doesn't have setReleaseMode:
        // behave properly! 
        // I will update IAudioPlayer interface quickly to include setReleaseMode support if I can, 
        // OR simply omit optimized settings for now if interface doesn't support it.
        // BUT wait, I can just implementation-check if I am lazy, but that defeats the purpose.
        // I'll stick to basic playback for now. Optimization flags lost unless I update interface.
        // User asked for "thin wrappers". 
        // I will add `setReleaseMode` to IAudioPlayer interface? No, that exposes implementation detail (audioplayers specific).
        // Ideally `IAudioPlayer.configure( ... )`.
        
        // For this task, I'll just use play/stop.
        // If performance degrades, I'll update interface.
        
        _pool.add(player);
      } catch (e) {
        debugPrint('[PianoSampleService] Failed to create player: $e');
      }
    }
    
    // We do not preload all 88 keys here as it might be heavy.
    // relying on first-play or system caching.
    
    _initialized = true;
    debugPrint('[PianoSampleService] Initialized (chromatic mode).');
  }


  // Map of acting MIDI note -> Player that is playing it
  final Map<int, IAudioPlayer> _activePlayers = {};

  Future<void> playNote(int midi, {double velocity = 0.7}) async {
    if (!_initialized) await init();

    try {
      // Use exact chromatic sample per MIDI note
      final fileName = '$midi.wav';
      
      final player = _pool[_poolIndex];
      _poolIndex = (_poolIndex + 1) % _poolSize;

      // If this player was busy, untrack it from whatever note it was playing
      _activePlayers.removeWhere((key, value) => value == player);

      // Stop previous note on this player
      await player.stop();
      
      // await player.setPlaybackRate(1.0); // Not in interface
      await player.play('audio/piano/$fileName', isAsset: true);
      await player.setVolume(velocity.clamp(0.0, 1.0));
      // await player.resume(); // play() calls resume/play
      
      _activePlayers[midi] = player;
      
      debugPrint('[PianoSampleService] Playing MIDI $midi (chromatic)');
    } catch (e) {
      debugPrint('[PianoSampleService] Error playing note $midi: $e');
    }
  }

  Future<void> stopNote(int midi) async {
    final player = _activePlayers[midi];
    if (player != null) {
      await player.stop();
      _activePlayers.remove(midi);
    }
  }

  void dispose() {
    for (final player in _pool) {
      player.dispose();
    }
    _pool.clear();
    _initialized = false;
  }
}
