
import 'dart:async';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PianoSampleService {
  static final PianoSampleService _instance = PianoSampleService._internal();
  factory PianoSampleService() => _instance;
  PianoSampleService._internal();

  static PianoSampleService get instance => _instance;

  // Pool of players to allow polyphony
  final List<AudioPlayer> _pool = [];
  static const int _poolSize = 8;
  int _poolIndex = 0;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    
    debugPrint('[PianoSampleService] Initializing $_poolSize players...');
    for (int i = 0; i < _poolSize; i++) {
      final player = AudioPlayer();
      await player.setReleaseMode(ReleaseMode.stop);
      // Low latency mode for Android
      await player.setPlayerMode(PlayerMode.lowLatency); 
      _pool.add(player);
    }
    
    // We do not preload all 88 keys here as it might be heavy.
    // relying on first-play or system caching.
    
    _initialized = true;
    debugPrint('[PianoSampleService] Initialized (chromatic mode).');
  }


  // Map of acting MIDI note -> Player that is playing it
  final Map<int, AudioPlayer> _activePlayers = {};

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
      
      await player.setPlaybackRate(1.0); // Exact pitch
      await player.setSource(AssetSource('audio/piano/$fileName'));
      await player.setVolume(velocity.clamp(0.0, 1.0));
      await player.resume();
      
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
