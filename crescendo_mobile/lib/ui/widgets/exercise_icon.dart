import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ExerciseIcon extends StatelessWidget {
  final String iconKey;
  final double size;
  final Color? color;

  const ExerciseIcon({
    super.key,
    required this.iconKey,
    this.size = 28,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Icon(
      _iconForKey(iconKey),
      size: size,
      color: color ?? AppColors.textPrimary,
    );
  }

  IconData _iconForKey(String key) {
    switch (key) {
      case 'breath':
        return Icons.air;
      case 'sovt':
        return Icons.spa;
      case 'onset':
        return Icons.bolt;
      case 'resonance':
        return Icons.graphic_eq;
      case 'range':
        return Icons.swap_vert;
      case 'register':
        return Icons.layers;
      case 'vowel':
        return Icons.record_voice_over;
      case 'intonation':
        return Icons.hearing;
      case 'agility':
        return Icons.speed;
      case 'articulation':
        return Icons.keyboard_voice;
      case 'dynamics':
        return Icons.volume_up;
      case 'endurance':
        return Icons.timer;
      case 'recovery':
        return Icons.self_improvement;
      case 'pitch':
        return Icons.multiline_chart;
      case 'hold':
        return Icons.pause_circle_filled;
      case 'listen':
        return Icons.music_note;
      case 'scale':
        return Icons.show_chart;
      case 'arpeggio':
        return Icons.stacked_line_chart;
      case 'siren':
        return Icons.waves;
      default:
        return Icons.music_note;
    }
  }
}
