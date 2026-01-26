import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

import 'preview_asset_service.dart';
import 'sine_sweep_service.dart';
import '../utils/audio_constants.dart';
import 'midi_preview_generator.dart';
import '../models/vocal_exercise.dart';
import '../audio/reference_midi_synth.dart';
import '../audio/midi_playback_config.dart';

/// Service for playing exercise preview audio.
/// Uses MIDI for non-glide exercises, WAV assets for glide exercises.
class PreviewAudioService {
  final AudioPlayer _player = AudioPlayer();
  final SineSweepService _sweepService = SineSweepService(sampleRate: AudioConstants.audioSampleRate);
  final ReferenceMidiSynth _midiSynth = ReferenceMidiSynth();
  StreamSubscription<void>? _completeSub;
  Completer<void>? _playbackCompleter;
  int _previewRunId = 0;

  /// Play preview for an exercise.
  /// Returns a Future that completes when playback finishes or is stopped.
  /// 
  /// Routing logic:
  /// - If exercise.isGlide == true: Use WAV asset (or generate sine sweep for NG slides)
  /// - If exercise.isGlide == false: Use MIDI preview
  Future<void> playPreview(VocalExercise exercise) async {
    // Stop any existing playback
    await stop();
    
    // Route based on exercise type
    if (exercise.isGlide) {
      // Glide exercises: Use WAV assets or generate sine sweep
      await _playWavPreview(exercise);
    } else {
      // Non-glide exercises: Use MIDI preview
      await _playMidiPreview(exercise);
    }
  }

  /// Play WAV preview for glide exercises
  Future<void> _playWavPreview(VocalExercise exercise) async {
    final exerciseId = exercise.id;
    final assetPath = PreviewAssetService.getPreviewAssetPath(exerciseId);
    
    final String audioPath;
    
    if (exerciseId == 'ng_slides') {
      // Special case: NG Slides uses real-time sine sweep
      audioPath = await _generateNgSlideSweep();
    } else if (assetPath != null) {
      // Load bundled asset
      final loadedPath = await _loadAsset(assetPath);
      if (loadedPath == null) {
        PreviewAssetService.logMissingAsset(assetPath);
        return; // Fail silently
      }
      audioPath = loadedPath;
    } else {
      // No preview available
      if (kDebugMode) {
        debugPrint('[PreviewAudio] No WAV preview available for glide exercise: $exerciseId');
      }
      return;
    }
    
    // Play the audio
    _playbackCompleter = Completer<void>();
    
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!_playbackCompleter!.isCompleted) {
        _playbackCompleter!.complete();
      }
    });
    
    try {
      await _player.play(DeviceFileSource(audioPath));
      await _playbackCompleter!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (kDebugMode) {
            debugPrint('[PreviewAudio] Playback timeout');
          }
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PreviewAudio] Playback error: $e');
      }
      if (!_playbackCompleter!.isCompleted) {
        _playbackCompleter!.completeError(e);
      }
    } finally {
      await _completeSub?.cancel();
      _completeSub = null;
      _playbackCompleter = null;
    }
  }

  /// Play MIDI preview for non-glide exercises
  Future<void> _playMidiPreview(VocalExercise exercise) async {
    // Generate preview notes (single iteration at C4)
    final previewNotes = MidiPreviewGenerator.generatePreview(exercise);
    
    if (previewNotes.isEmpty) {
      if (kDebugMode) {
        debugPrint('[PreviewAudio] No MIDI preview notes generated for exercise: ${exercise.id}');
      }
      return;
    }

    // Calculate preview duration
    final maxEndSec = previewNotes.map((n) => n.endSec).reduce((a, b) => a > b ? a : b);
    final previewDurationSec = maxEndSec;

    // Play MIDI sequence
    _previewRunId++;
    final startEpochMs = DateTime.now().millisecondsSinceEpoch;
    
    try {
      await _midiSynth.playSequence(
        notes: previewNotes,
        leadInSec: 0.0, // No lead-in for previews
        runId: _previewRunId,
        startEpochMs: startEpochMs,
        config: MidiPlaybackConfig.exercise(), // Use same config as exercise playback
      );

      // Wait for playback to complete
      await Future.delayed(Duration(milliseconds: (previewDurationSec * 1000).round()));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PreviewAudio] MIDI preview playback error: $e');
      }
    }
  }

  /// Stop current playback.
  Future<void> stop() async {
    await _completeSub?.cancel();
    _completeSub = null;
    if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
      _playbackCompleter!.complete();
    }
    _playbackCompleter = null;
    await _player.stop();
    await _midiSynth.stop(); // Stop MIDI playback if active
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }

  /// Load an asset from the app bundle and copy to temp directory for playback.
  Future<String?> _loadAsset(String assetPath) async {
    try {
      final byteData = await rootBundle.load(assetPath);
      final bytes = byteData.buffer.asUint8List();
      
      final dir = await getTemporaryDirectory();
      final fileName = p.basename(assetPath);
      final tempPath = p.join(dir.path, 'preview_$fileName');
      final file = File(tempPath);
      await file.writeAsBytes(bytes, flush: true);
      
      return tempPath;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PreviewAudio] Failed to load asset $assetPath: $e');
      }
      return null;
    }
  }

  /// Generate real-time sine sweep for NG Slide preview.
  /// Creates a smooth upward glide from bottom note to top note.
  Future<String> _generateNgSlideSweep() async {
    // NG Slide pattern: bottom note -> top note (upward glide)
    // Use C4 (60) to E5 (76) as a representative range
    const startMidi = 60.0; // C4
    const endMidi = 76.0; // E5
    const durationSeconds = 2.0; // 2 second sweep
    const fadeSeconds = 0.05; // Short fade
    
    // Generate sweep samples
    final samples = _sweepService.generateSineSweep(
      midiStart: startMidi,
      midiEnd: endMidi,
      durationSeconds: durationSeconds,
      amplitude: 0.2,
      fadeSeconds: fadeSeconds,
    );
    
    // Encode to WAV
    final wavBytes = _sweepService.encodeWav16Mono(samples);
    
    // Write to temp file
    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, 'ng_slide_preview_${DateTime.now().millisecondsSinceEpoch}.wav');
    final file = File(path);
    await file.writeAsBytes(wavBytes, flush: true);
    
    return path;
  }
}
