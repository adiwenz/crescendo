import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

import 'preview_asset_service.dart';
import 'sine_sweep_service.dart';
import '../models/vocal_exercise.dart';

/// Service for playing exercise preview audio.
/// Uses pre-baked WAV assets for most exercises, real-time sine sweep for NG Slides.
class PreviewAudioService {
  final AudioPlayer _player = AudioPlayer();
  final SineSweepService _sweepService = SineSweepService(sampleRate: 44100);
  StreamSubscription<void>? _completeSub;
  Completer<void>? _playbackCompleter;

  /// Play preview for an exercise.
  /// Returns a Future that completes when playback finishes or is stopped.
  Future<void> playPreview(VocalExercise exercise) async {
    // Stop any existing playback
    await stop();
    
    final exerciseId = exercise.id;
    final assetPath = PreviewAssetService.getPreviewAssetPath(exerciseId);
    
    String? audioPath;
    
    if (exerciseId == 'ng_slides') {
      // Special case: NG Slides uses real-time sine sweep
      audioPath = await _generateNgSlideSweep();
    } else if (assetPath != null) {
      // Load bundled asset
      audioPath = await _loadAsset(assetPath);
      if (audioPath == null) {
        PreviewAssetService.logMissingAsset(assetPath);
        return; // Fail silently
      }
    } else {
      // No preview available
      if (kDebugMode) {
        debugPrint('[PreviewAudio] No preview available for exercise: $exerciseId');
      }
      return;
    }
    
    if (audioPath == null) return;
    
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

  /// Stop current playback.
  Future<void> stop() async {
    await _completeSub?.cancel();
    _completeSub = null;
    if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
      _playbackCompleter!.complete();
    }
    _playbackCompleter = null;
    await _player.stop();
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
