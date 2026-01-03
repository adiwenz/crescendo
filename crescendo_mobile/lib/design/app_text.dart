import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppText {
  static TextStyle get h1 => GoogleFonts.manrope(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static TextStyle get h2 => GoogleFonts.manrope(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle get body => GoogleFonts.manrope(
    fontSize: 14,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  static TextStyle get caption => GoogleFonts.manrope(
    fontSize: 12,
    color: AppColors.textSecondary,
  );
}
