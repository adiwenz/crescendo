import 'package:flutter/material.dart';

/// Centralized colors and styles for the Home screen.
/// Update colors and styling here to change the Home screen appearance.
class HomeScreenStyles {
  // Background gradient colors
  static const Color bgTop = Color(0xFFF7FBFF); // Very light blue
  static const Color bgMid = Color(0xFFF3E8FF); // Pale lavender
  static const Color bgBottom = Color(0xFFE6E6FA); // Soft periwinkle

  // Accent colors
  static const Color accentPurple =
      Color.fromARGB(255, 217, 204, 248); // Saturated purple
  static const Color accentBlue =
      Color.fromARGB(255, 190, 218, 250); // Light blue

  // Card styling
  static const Color cardFill = Color(0xFFFFFFFF); // White
  static const double cardOpacity = 0.75; // 0.70-0.85 range
  static const Color cardBorder = Color(0x40FFFFFF); // White at ~0.25 opacity
  static const double cardBorderWidth = 1.0;
  static const double cardBorderRadius = 22.0; // 20-26 range
  static const Color cardShadowColor =
      Color(0x14000000); // Black at ~0.08 opacity
  static const double cardShadowBlur = 20.0;
  static const double cardShadowSpread = 0.0;
  static const Offset cardShadowOffset = Offset(0, 4);

  // Text colors
  static const Color textPrimary = Color(0xFF0D0D0D); // Near-black/navy
  static const Color textSecondary = Color(0xFF5C6270); // Muted slate

  // Icon colors
  static const Color iconActive = accentPurple;
  static const Color iconInactive = Color(0xFF9CA3AF); // Mid-gray

  // Progress bar
  static const Color progressBarBackground =
      Color(0x66FFFFFF); // White at ~0.4 opacity
  static const Color progressBarFill = accentPurple;

  // Hero header background colors
  static const Color heroBgBaseTop = Color(0xFFF7FBFF);
  static const Color heroBgBaseBottom = Color(0xFFFFFFFF);
  static const Color heroWave1Top = Color(0xFFECF4FF);
  static const Color heroWave1Bottom = Color(0xFFDDEBFF);
  static const Color heroWave2Top = Color(0xFFFFF5EA);
  static const Color heroWave2Bottom = Color(0xFFFFF1D6);
  static const Color heroBokehColor =
      Color(0x1F4C6FFF); // Accent with 0.12 opacity

  // Continue card specific
  static const Color continueCardOverlay =
      Color(0x0DFFFFFF); // White at 0.05 opacity
  static const Color continueCardPillBg =
      Color(0xB3FFFFFF); // White at 0.7 opacity
  static const double continueCardBorderRadius = 20.0;

  // Category banner row specific
  static const Color categoryBannerBg = Color(0xFFFFFFFF);
  static const double categoryBannerBorderRadius = 20.0;
  static const Color categoryBannerShadowColor =
      Color(0x0F000000); // Black at 0.06 opacity
  static const double categoryBannerShadowBlur = 14.0;
  static const Offset categoryBannerShadowOffset = Offset(0, 6);

  // Gradients
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgTop, bgMid, bgBottom],
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient homeScreenGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [accentPurple, accentBlue],
  );

  static const LinearGradient heroBaseGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [heroBgBaseTop, heroBgBaseBottom],
  );

  static const LinearGradient heroWave1Gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [heroWave1Top, heroWave1Bottom],
  );

  static const LinearGradient heroWave2Gradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [heroWave2Top, heroWave2Bottom],
  );

  // Box decorations
  static BoxDecoration get frostedGlassCard => BoxDecoration(
        color: cardFill.withOpacity(cardOpacity),
        borderRadius: BorderRadius.circular(cardBorderRadius),
        border: Border.all(
          color: cardBorder,
          width: cardBorderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: cardShadowColor,
            blurRadius: cardShadowBlur,
            spreadRadius: cardShadowSpread,
            offset: cardShadowOffset,
          ),
        ],
      );

  static BoxDecoration get categoryBannerDecoration => BoxDecoration(
        color: categoryBannerBg,
        borderRadius: BorderRadius.circular(categoryBannerBorderRadius),
        boxShadow: [
          BoxShadow(
            color: categoryBannerShadowColor,
            blurRadius: categoryBannerShadowBlur,
            offset: categoryBannerShadowOffset,
          ),
        ],
      );

  // Text styles (if needed beyond AppText)
  // fontFamily is not specified - it will be inherited from ThemeData.fontFamily
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: textPrimary,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: textPrimary,
  );

  static const TextStyle cardSubtitle = TextStyle(
    fontSize: 14,
    color: textSecondary,
  );

  static const TextStyle categoryTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: textPrimary,
  );

  static const TextStyle categorySubtitle = TextStyle(
    fontSize: 14,
    color: textSecondary,
  );

  static const TextStyle pillText = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );
}
