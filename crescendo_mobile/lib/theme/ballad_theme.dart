
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class BalladTheme {
  // --- Colors ---
  static const Color bgTop = Color(0xFF0B2A57);
  static const Color bgMid = Color(0xFF3E6F86);
  static const Color bgBottom = Color(0xFFBFEFE8);

  static const Color accentBlue = Color(0xFF2F8BFF);
  static const Color accentPurple = Color(0xFF6A2CFF);
  static const Color accentLavender = Color(0xFFB9A4FF);
  static const Color accentPink = Color(0xFFFF8CCB);
  static const Color accentTeal = Color(0xFF3BE5D0);
  static const Color accentGold = Color(0xFFFFD700); // Added for timeline

  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xB3FFFFFF); // 70%

  // --- Gradients ---
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgTop, bgMid, bgBottom],
    stops: [0.0, 0.6, 1.0],
  );

  static const LinearGradient primaryButtonGradient = LinearGradient(
    colors: [Color(0xFF6A2CFF), Color(0xFF2F8BFF)],
  );

  // --- Text Styles ---
  static TextStyle get titleLarge => GoogleFonts.dmSerifDisplay(
        color: textPrimary,
        fontSize: 32,
        fontWeight: FontWeight.w400,
      );

  static TextStyle get titleMedium => GoogleFonts.dmSerifDisplay(
        color: textPrimary,
        fontSize: 24,
        fontWeight: FontWeight.w400,
      );

  static TextStyle get bodyLarge => GoogleFonts.manrope(
        color: textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w400,
      );

  static TextStyle get bodyMedium => GoogleFonts.manrope(
        color: textPrimary, // Or secondary
        fontSize: 14,
        fontWeight: FontWeight.w400,
      );

  static TextStyle get bodySmall => GoogleFonts.manrope(
        color: textSecondary, 
        fontSize: 12,
        fontWeight: FontWeight.w400,
      );
      
  static TextStyle get labelLarge => GoogleFonts.manrope( // Button text
        color: textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get labelSmall => GoogleFonts.manrope(
        color: textPrimary,
        fontSize: 10,
        fontWeight: FontWeight.w500,
      );
}
