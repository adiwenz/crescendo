import 'dart:convert';
import 'package:flutter/services.dart';

/// Resolves asset paths for exercise reference audio files.
/// 
/// For non-glide exercises, returns paths to:
/// - M4A file: assets/audio/exercises/<exerciseId>_fullrange.m4a
/// - JSON index: assets/audio/exercises/<exerciseId>_fullrange_index.json
class ExerciseAudioAssetResolver {
  /// Get the M4A asset path for an exercise
  static String getM4aAssetPath(String exerciseId) {
    return 'assets/audio/exercises/${exerciseId}_fullrange.m4a';
  }

  /// Get the JSON index asset path for an exercise
  static String getIndexAssetPath(String exerciseId) {
    return 'assets/audio/exercises/${exerciseId}_fullrange_index.json';
  }

  /// Check if an exercise has a full-range M4A asset
  static Future<bool> hasAsset(String exerciseId) async {
    try {
      await rootBundle.load(getM4aAssetPath(exerciseId));
      await rootBundle.load(getIndexAssetPath(exerciseId));
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Load the JSON index for an exercise
  static Future<Map<String, dynamic>> loadIndex(String exerciseId) async {
    final indexPath = getIndexAssetPath(exerciseId);
    final indexString = await rootBundle.loadString(indexPath);
    return Map<String, dynamic>.from(
      // ignore: avoid_dynamic_calls
      jsonDecode(indexString) as Map,
    );
  }

  /// List all exercise IDs that have available assets
  /// This checks against a known list of exercise IDs from exercises.json
  static Future<List<String>> listAvailableExercises() async {
    // Known exercise IDs from exercises.json (non-glide exercises)
    const knownExerciseIds = [
      'vv_zz_scales',
      'humming_scales',
      'balanced_onset',
      'chest_voice_scales',
      'head_voice_scales',
      'five_tone_scales',
      'scale_degrees',
      'forward_placement',
      'mask_resonance',
      'arpeggios',
      'mix_bridging',
      'sustained_s_z',
      'lip_trills',
      'sustained_pitch_holds',
      'fast_three_note_patterns',
      'staccato_bursts',
      'descending_runs',
      'interval_training',
      'descending_head_to_chest',
    ];

    final available = <String>[];
    for (final exerciseId in knownExerciseIds) {
      if (await hasAsset(exerciseId)) {
        available.add(exerciseId);
      }
    }
    return available;
  }
}
