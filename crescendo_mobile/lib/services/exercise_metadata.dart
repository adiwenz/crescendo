import '../models/vocal_exercise.dart';

enum PreviewAudioStyle {
  none,
  sineTone,
  sineSweep,
}

enum ExerciseTargetStyle {
  endpointsGlide,
  discreteNotes,
  hold,
  promptTimer,
}

class ExerciseMetadata {
  final bool previewSupported;
  final bool usesPitchHighway;
  final PreviewAudioStyle previewAudioStyle;
  final ExerciseTargetStyle exerciseTargetStyle;

  const ExerciseMetadata({
    required this.previewSupported,
    required this.usesPitchHighway,
    required this.previewAudioStyle,
    required this.exerciseTargetStyle,
  });

  static ExerciseMetadata forExercise(VocalExercise exercise) {
    // Special cases
    switch (exercise.id) {
      case 'tongue_trills':
        return const ExerciseMetadata(
          previewSupported: false,
          usesPitchHighway: false,
          previewAudioStyle: PreviewAudioStyle.none,
          exerciseTargetStyle: ExerciseTargetStyle.promptTimer,
        );
      case 'yawn_sigh':
        return const ExerciseMetadata(
          previewSupported: false,
          usesPitchHighway: false,
          previewAudioStyle: PreviewAudioStyle.none,
          exerciseTargetStyle: ExerciseTargetStyle.promptTimer,
        );
      case 'ng_slides':
        return const ExerciseMetadata(
          previewSupported: true,
          usesPitchHighway: true,
          previewAudioStyle: PreviewAudioStyle.sineSweep,
          exerciseTargetStyle: ExerciseTargetStyle.endpointsGlide,
        );
      case 'sirens':
        return const ExerciseMetadata(
          previewSupported: true,
          usesPitchHighway: true,
          previewAudioStyle: PreviewAudioStyle.sineSweep,
          exerciseTargetStyle: ExerciseTargetStyle.endpointsGlide,
        );
      case 'sustained_pitch_holds':
        return const ExerciseMetadata(
          previewSupported: true,
          usesPitchHighway: false,
          previewAudioStyle: PreviewAudioStyle.sineTone,
          exerciseTargetStyle: ExerciseTargetStyle.hold,
        );
      case 'interval_training':
        return const ExerciseMetadata(
          previewSupported: true,
          usesPitchHighway: false,
          previewAudioStyle: PreviewAudioStyle.sineTone,
          exerciseTargetStyle: ExerciseTargetStyle.discreteNotes,
        );
      case 'fast_three_note_patterns':
        return const ExerciseMetadata(
          previewSupported: true,
          usesPitchHighway: true,
          previewAudioStyle: PreviewAudioStyle.sineTone,
          exerciseTargetStyle: ExerciseTargetStyle.discreteNotes,
        );
    }

    // Default based on exercise type
    switch (exercise.type) {
      case ExerciseType.pitchHighway:
        if (exercise.highwaySpec?.segments.isEmpty ?? true) {
          return const ExerciseMetadata(
            previewSupported: false,
            usesPitchHighway: true,
            previewAudioStyle: PreviewAudioStyle.none,
            exerciseTargetStyle: ExerciseTargetStyle.discreteNotes,
          );
        }
        return const ExerciseMetadata(
          previewSupported: true,
          usesPitchHighway: true,
          previewAudioStyle: PreviewAudioStyle.sineTone,
          exerciseTargetStyle: ExerciseTargetStyle.discreteNotes,
        );
      case ExerciseType.breathTimer:
      case ExerciseType.sovtTimer:
      case ExerciseType.cooldownRecovery:
        return const ExerciseMetadata(
          previewSupported: false,
          usesPitchHighway: false,
          previewAudioStyle: PreviewAudioStyle.none,
          exerciseTargetStyle: ExerciseTargetStyle.promptTimer,
        );
      case ExerciseType.sustainedPitchHold:
        return const ExerciseMetadata(
          previewSupported: true,
          usesPitchHighway: false,
          previewAudioStyle: PreviewAudioStyle.sineTone,
          exerciseTargetStyle: ExerciseTargetStyle.hold,
        );
      case ExerciseType.pitchMatchListening:
        return const ExerciseMetadata(
          previewSupported: true,
          usesPitchHighway: false,
          previewAudioStyle: PreviewAudioStyle.sineTone,
          exerciseTargetStyle: ExerciseTargetStyle.discreteNotes,
        );
      default:
        return const ExerciseMetadata(
          previewSupported: false,
          usesPitchHighway: false,
          previewAudioStyle: PreviewAudioStyle.none,
          exerciseTargetStyle: ExerciseTargetStyle.discreteNotes,
        );
    }
  }
}
