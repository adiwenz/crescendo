import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppText {
  // Text styles that inherit Manrope fontFamily from ThemeData
  // fontFamily is not specified here - it will be inherited from ThemeData.fontFamily
  static const TextStyle h1 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: AppColors.textSecondary,
  );

  // Breathing Exercise Typography System
  // All text on breathing/countdown screens must use these styles

  /// Exercise title (e.g., "Appoggio Breathing")
  static const TextStyle exerciseTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w500,
    fontFamily: 'Manrope',
    color: AppColors.textPrimary,
  );

  /// Meta label (e.g., "Total Time Remaining")
  static const TextStyle metaLabel = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.5,
    fontFamily: 'Manrope',
    color: AppColors.textSecondary,
  );

  /// Meta value (e.g., "21s")
  static const TextStyle metaValue = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w500,
    fontFamily: 'Manrope',
    color: AppColors.textPrimary,
  );

  /// Countdown number inside circle during exercise (e.g., "3", "2", "1")
  static const TextStyle countdownNumber = TextStyle(
    fontSize: 80,
    fontWeight: FontWeight.w500,
    fontFamily: 'Manrope',
    color: Colors.white,
  );

  /// Phase label (e.g., "Inhale", "Exhale", "Hold")
  /// Also used for pre-roll countdown (e.g., "3", "2", "1" below circle)
  /// Same size as metaValue for visual consistency
  static const TextStyle phaseLabel = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    fontFamily: 'Manrope',
    color: AppColors.textPrimary,
  );
}
